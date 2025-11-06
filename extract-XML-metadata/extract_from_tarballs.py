#!/usr/bin/env python3
"""
Streaming XML Metadata Extractor from Tar.gz Archives

Extracts XML files from tar.gz archives and processes them directly in memory
without writing intermediate files to disk. Only the final output is written.

Usage:
    python extract_from_tarballs.py [options] <tar_directory>

Examples:
    python extract_from_tarballs.py /Volumes/DSST_backup2025/osm/pmcoa/raw_download/
    python extract_from_tarballs.py --format parquet -o output.parquet /path/to/tarballs/
    python extract_from_tarballs.py --limit 5 /path/to/tarballs/  # Process only first 5 tar.gz files
"""

import argparse
import sys
import tarfile
import gzip
import io
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, List, Optional, Union, BinaryIO
import pandas as pd
from datetime import datetime
import time


# Import the column definitions and extractor class from our original script
# We'll need to modify it to work with in-memory data
import os

# Define all 120 columns in order (same as original)
ALL_COLUMNS = [
    # Basic metadata (copied)
    'pmid', 'pmcid_pmc', 'pmcid_uid', 'doi', 'filename', 'journal', 'publisher',
    'affiliation_institution', 'affiliation_country', 'year_epub', 'year_ppub',

    # COI columns
    'is_coi_pred', 'coi_text', 'is_coi_pmc_fn', 'is_coi_pmc_title', 'is_relevant_coi',
    'is_relevant_coi_hi', 'is_relevant_coi_lo', 'is_explicit_coi', 'coi_1', 'coi_2',
    'coi_disclosure_1', 'commercial_1', 'benefit_1', 'consultant_1', 'grants_1',
    'brief_1', 'fees_1', 'consults_1', 'connect_1', 'connect_2', 'commercial_ack_1',
    'rights_1', 'founder_1', 'advisor_1', 'paid_1', 'board_1', 'no_coi_1',
    'no_funder_role_1',

    # Funding columns
    'is_fund_pred', 'fund_text', 'fund_pmc_institute', 'fund_pmc_source',
    'fund_pmc_anysource', 'is_fund_pmc_group', 'is_fund_pmc_title',
    'is_fund_pmc_anysource', 'is_relevant_fund', 'is_explicit_fund', 'support_1',
    'support_3', 'support_4', 'support_5', 'support_6', 'support_7', 'support_8',
    'support_9', 'support_10', 'developed_1', 'received_1', 'received_2',
    'recipient_1', 'authors_1', 'authors_2', 'thank_1', 'thank_2', 'fund_1',
    'fund_2', 'fund_3', 'supported_1', 'financial_1', 'financial_2', 'financial_3',
    'grant_1', 'french_1', 'common_1', 'common_2', 'common_3', 'common_4',
    'common_5', 'acknow_1', 'disclosure_1', 'disclosure_2', 'fund_ack', 'project_ack',

    # Registration columns
    'is_register_pred', 'register_text', 'type', 'is_research', 'is_review',
    'is_reg_pmc_title', 'is_relevant_reg', 'is_method', 'is_NCT', 'is_explicit_reg',
    'prospero_1', 'registered_1', 'registered_2', 'registered_3', 'registered_4',
    'registered_5', 'not_registered_1', 'registration_1', 'registration_2',
    'registration_3', 'registration_4', 'registry_1', 'reg_title_1', 'reg_title_2',
    'reg_title_3', 'reg_title_4', 'funded_ct_1', 'ct_2', 'ct_3', 'protocol_1',

    # Open science columns
    'is_success', 'is_open_data', 'is_open_code', 'is_relevant_code', 'is_relevant_data',

    # New columns
    'file_size', 'chars_in_body'
]


class StreamingXMLMetadataExtractor:
    """Extracts metadata from XML data in memory (streams)."""

    NAMESPACES = {
        'xlink': 'http://www.w3.org/1999/xlink',
        'mml': 'http://www.w3.org/1998/Math/MathML',
        'ali': 'http://www.niso.org/schemas/ali/1.0/'
    }

    def __init__(self):
        self.records = []

    def extract_text(self, element: Optional[ET.Element]) -> str:
        """Extract all text content from an element and its children."""
        if element is None:
            return ''

        texts = []
        if element.text:
            texts.append(element.text.strip())

        for child in element:
            child_text = self.extract_text(child)
            if child_text:
                texts.append(child_text)
            if child.tail:
                texts.append(child.tail.strip())

        return ' '.join(filter(None, texts))

    def extract_article_ids(self, root: ET.Element) -> Dict[str, str]:
        """Extract article IDs (PMID, PMCID, DOI)."""
        ids = {'pmid': '', 'pmcid_pmc': '', 'pmcid_uid': '', 'doi': ''}

        article_ids = root.findall(".//article-meta/article-id")

        for aid in article_ids:
            pub_id_type = aid.get('pub-id-type', '')
            text = (aid.text or '').strip()

            if pub_id_type == 'pmid':
                ids['pmid'] = text
            elif pub_id_type == 'pmc':
                ids['pmcid_pmc'] = text
            elif pub_id_type == 'pmcid':
                ids['pmcid_uid'] = text
            elif pub_id_type == 'doi':
                ids['doi'] = text

        return ids

    def extract_journal_info(self, root: ET.Element) -> Dict[str, str]:
        """Extract journal and publisher information."""
        info = {'journal': '', 'publisher': ''}

        journal_title = root.find(".//journal-meta/journal-title-group/journal-title")
        if journal_title is not None:
            info['journal'] = self.extract_text(journal_title)

        publisher_parts = []
        publisher_name = root.find(".//journal-meta/publisher/publisher-name")
        if publisher_name is not None:
            publisher_parts.append(self.extract_text(publisher_name))

        publisher_loc = root.find(".//journal-meta/publisher/publisher-loc")
        if publisher_loc is not None:
            publisher_parts.append(self.extract_text(publisher_loc))

        if publisher_parts:
            info['publisher'] = '; '.join(publisher_parts)

        return info

    def extract_affiliations(self, root: ET.Element) -> Dict[str, str]:
        """Extract author affiliation information."""
        affiliations = {'affiliation_institution': '', 'affiliation_country': ''}

        aff_elements = root.findall(".//contrib-group//aff")

        institutions = []
        countries = []

        for aff in aff_elements:
            inst = aff.find(".//institution")
            if inst is not None:
                inst_text = self.extract_text(inst)
                if inst_text:
                    institutions.append(inst_text)

            country = aff.find(".//country")
            if country is not None:
                country_text = self.extract_text(country)
                if country_text:
                    countries.append(country_text)

        if institutions:
            affiliations['affiliation_institution'] = '; '.join(dict.fromkeys(institutions))
        if countries:
            affiliations['affiliation_country'] = '; '.join(dict.fromkeys(countries))

        return affiliations

    def extract_pub_dates(self, root: ET.Element) -> Dict[str, str]:
        """Extract publication dates."""
        dates = {'year_epub': '', 'year_ppub': ''}

        pub_dates = root.findall(".//article-meta/pub-date")

        for pub_date in pub_dates:
            pub_type = pub_date.get('pub-type', '')
            year_elem = pub_date.find('year')

            if year_elem is not None:
                year = year_elem.text.strip() if year_elem.text else ''

                if pub_type == 'epub':
                    dates['year_epub'] = year
                elif pub_type == 'ppub':
                    dates['year_ppub'] = year

        return dates

    def extract_article_type(self, root: ET.Element) -> str:
        """Extract article type attribute."""
        article = root.find('.//article')
        if article is not None:
            return article.get('article-type', '')
        return ''

    def extract_coi_text(self, root: ET.Element) -> str:
        """Extract conflict of interest statement."""
        fn_elements = root.findall(".//fn[@fn-type]")

        for fn in fn_elements:
            fn_type = fn.get('fn-type', '').lower()
            if 'coi' in fn_type or 'conflict' in fn_type:
                return self.extract_text(fn)

        return ''

    def extract_funding_text(self, root: ET.Element) -> Dict[str, str]:
        """Extract funding information."""
        funding = {
            'fund_text': '',
            'fund_pmc_institute': '',
            'fund_pmc_source': '',
            'fund_pmc_anysource': ''
        }

        fn_elements = root.findall(".//fn[@fn-type]")
        for fn in fn_elements:
            fn_type = fn.get('fn-type', '').lower()
            if 'financial' in fn_type or 'funding' in fn_type:
                funding['fund_text'] = self.extract_text(fn)
                break

        funding_group = root.find(".//funding-group")
        if funding_group is not None:
            institutions = []
            institution_elems = funding_group.findall(".//institution")
            for inst in institution_elems:
                inst_text = self.extract_text(inst)
                if inst_text:
                    institutions.append(inst_text)

            if institutions:
                funding['fund_pmc_institute'] = '; '.join(institutions)

            funding_sources = []
            institution_wraps = funding_group.findall(".//institution-wrap")
            for wrap in institution_wraps:
                parts = []
                inst = wrap.find(".//institution")
                if inst is not None:
                    parts.append(self.extract_text(inst))

                inst_id = wrap.find(".//institution-id")
                if inst_id is not None:
                    parts.append(self.extract_text(inst_id))

                if parts:
                    funding_sources.append(''.join(parts))

            if funding_sources:
                funding['fund_pmc_source'] = '; '.join(funding_sources)
                funding['fund_pmc_anysource'] = funding['fund_pmc_source']

        return funding

    def extract_registration_text(self, root: ET.Element) -> str:
        """Extract trial registration information."""
        custom_metas = root.findall(".//custom-meta")
        for meta in custom_metas:
            meta_name = meta.find("meta-name")
            if meta_name is not None and 'regist' in self.extract_text(meta_name).lower():
                meta_value = meta.find("meta-value")
                if meta_value is not None:
                    return self.extract_text(meta_value)

        ext_links = root.findall(".//ext-link")
        for link in ext_links:
            link_text = self.extract_text(link)
            if 'nct' in link_text.lower() or 'clinical' in link_text.lower() or 'trial' in link_text.lower():
                return link_text

        return ''

    def calculate_body_chars(self, root: ET.Element) -> int:
        """Calculate number of characters in article body."""
        body = root.find(".//body")
        if body is not None:
            body_text = self.extract_text(body)
            return len(body_text)
        return 0

    def process_xml_data(self, xml_data: bytes, source_name: str, file_size: int) -> Dict[str, Union[str, int]]:
        """Process XML data from memory and extract metadata."""
        record = {col: None for col in ALL_COLUMNS}

        try:
            record['file_size'] = file_size
            record['filename'] = source_name

            # Parse XML from bytes
            root = ET.fromstring(xml_data)

            # Extract all metadata
            record.update(self.extract_article_ids(root))
            record.update(self.extract_journal_info(root))
            record.update(self.extract_affiliations(root))
            record.update(self.extract_pub_dates(root))
            record['type'] = self.extract_article_type(root)
            record['coi_text'] = self.extract_coi_text(root)
            record.update(self.extract_funding_text(root))
            record['register_text'] = self.extract_registration_text(root)
            record['chars_in_body'] = self.calculate_body_chars(root)

        except Exception as e:
            print(f"Error processing {source_name}: {e}", file=sys.stderr)
            record['filename'] = source_name

        return record

    def process_tarball(self, tarball_path: Path) -> int:
        """Extract and process all XML files from a tar.gz archive."""
        count = 0

        try:
            with tarfile.open(tarball_path, 'r:gz') as tar:
                members = tar.getmembers()

                for member in members:
                    if member.name.endswith('.xml') and member.isfile():
                        try:
                            # Extract file to memory
                            f = tar.extractfile(member)
                            if f is not None:
                                xml_data = f.read()

                                # Process the XML data
                                source_name = f"{tarball_path.name}:{member.name}"
                                record = self.process_xml_data(xml_data, source_name, member.size)
                                self.records.append(record)
                                count += 1

                        except Exception as e:
                            print(f"Error extracting {member.name} from {tarball_path.name}: {e}", file=sys.stderr)

        except Exception as e:
            print(f"Error opening tarball {tarball_path}: {e}", file=sys.stderr)

        return count

    def to_dataframe(self) -> pd.DataFrame:
        """Convert records to pandas DataFrame."""
        df = pd.DataFrame(self.records, columns=ALL_COLUMNS)
        return df

    def save_csv(self, output_path: Path):
        """Save records to CSV file."""
        df = self.to_dataframe()
        df.to_csv(output_path, index=False)
        print(f"\nSaved {len(df)} records to {output_path}")

    def save_parquet(self, output_path: Path):
        """Save records to Parquet file."""
        df = self.to_dataframe()
        df.to_parquet(output_path, index=False)
        print(f"\nSaved {len(df)} records to {output_path}")


def find_tarballs(directory: Path) -> List[Path]:
    """Find all .tar.gz files in directory."""
    tarballs = sorted(directory.glob('*.tar.gz'))
    return tarballs


def main():
    parser = argparse.ArgumentParser(
        description='Extract metadata from XML files in tar.gz archives (streaming mode - no intermediate files).',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s /path/to/tarballs/
  %(prog)s --format parquet -o output.parquet /path/to/tarballs/
  %(prog)s --limit 5 /path/to/tarballs/
  %(prog)s --pattern "oa_comm_xml.incr.2025-07-*" /path/to/tarballs/
        """
    )

    parser.add_argument(
        'tar_directory',
        type=str,
        help='Directory containing .tar.gz archives'
    )

    parser.add_argument(
        '-o', '--output',
        type=str,
        default=None,
        help='Output file path (default: streaming_metadata.csv or .parquet based on format)'
    )

    parser.add_argument(
        '-f', '--format',
        choices=['csv', 'parquet'],
        default='csv',
        help='Output format (default: csv)'
    )

    parser.add_argument(
        '--limit',
        type=int,
        default=None,
        help='Limit number of tar.gz files to process (for testing)'
    )

    parser.add_argument(
        '--pattern',
        type=str,
        default='*.tar.gz',
        help='Glob pattern for tar.gz files (default: *.tar.gz)'
    )

    args = parser.parse_args()

    tar_dir = Path(args.tar_directory)
    if not tar_dir.exists() or not tar_dir.is_dir():
        print(f"Error: Directory does not exist: {tar_dir}", file=sys.stderr)
        return 1

    # Determine output path
    if args.output:
        output_path = Path(args.output)
    else:
        extension = 'csv' if args.format == 'csv' else 'parquet'
        output_path = Path(f'streaming_metadata.{extension}')

    # Find all tar.gz files
    tarballs = sorted(tar_dir.glob(args.pattern))

    if not tarballs:
        print(f"No tar.gz files found matching pattern '{args.pattern}' in {tar_dir}", file=sys.stderr)
        return 1

    if args.limit:
        tarballs = tarballs[:args.limit]

    print(f"Found {len(tarballs)} tar.gz file(s) to process")
    print(f"Output: {output_path} ({args.format} format)")
    print("=" * 70)

    # Create extractor
    extractor = StreamingXMLMetadataExtractor()

    # Process all tarballs
    start_time = time.time()
    total_files = 0

    for i, tarball in enumerate(tarballs, 1):
        print(f"\n[{i}/{len(tarballs)}] Processing: {tarball.name}")
        tarball_start = time.time()

        count = extractor.process_tarball(tarball)
        total_files += count

        tarball_elapsed = time.time() - tarball_start
        if count > 0:
            print(f"  Extracted {count} XML files in {tarball_elapsed:.2f}s ({count/tarball_elapsed:.1f} files/sec)")
        else:
            print(f"  No XML files found")

    elapsed = time.time() - start_time

    # Save results
    if not extractor.records:
        print("\nNo records extracted. Exiting.", file=sys.stderr)
        return 1

    print("\n" + "=" * 70)
    print("SAVING RESULTS")
    print("=" * 70)

    if args.format == 'csv':
        extractor.save_csv(output_path)
    else:
        extractor.save_parquet(output_path)

    # Print summary
    print("\n" + "=" * 70)
    print("SUMMARY")
    print("=" * 70)
    print(f"  Tar.gz files processed: {len(tarballs)}")
    print(f"  Total XML files extracted: {total_files:,}")
    print(f"  Total processing time: {elapsed:.2f} seconds ({elapsed/60:.2f} minutes)")
    print(f"  Average rate: {total_files/elapsed:.1f} files/second")
    print(f"  Output format: {args.format}")
    print(f"  Output file: {output_path}")
    print(f"  Output size: {output_path.stat().st_size / 1024 / 1024:.2f} MB")

    return 0


if __name__ == '__main__':
    sys.exit(main())
