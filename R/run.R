library(magrittr)
library(nanoparquet)
source("xml_utils.R")
source("rt_coi_pmc.R")
source("rt_all_pmc.R")
source("rt_register_pmc.R")
source("rt_fund_pmc.R")
source("rt_data_code_pmc.R")
source("utils.R")

outDir <- Sys.getenv("R_OUTDIR", "/out")
inDir <- Sys.getenv("R_INDIR", "/in")
ident <- Sys.getenv("R_IDENTIFIER", "0")

vectorized_rt <- Vectorize(rt_all_pmc, vectorize.args=c("filename"), SIMPLIFY=F) # remap the rt_all_pmc function to run over vector

if (dir.exists(file.path(inDir))) {
	args <- list.files(file.path(inDir), ".*\\.xml") %>% lapply(., function(x) file.path(inDir, x))

	if (length(args) > 0) {
		out <- vectorized_rt(args) %>% Filter(function(x) length(x) == 116, .) %>% do.call(rbind, .) # run & bind into a big tibble

		dir.create(file.path(outDir), showWarnings=F)
		write_parquet(out, file.path(outDir, paste("out", ident, "parquet", sep=".")))
	}

}
