{
  description = "Packaging RTransparent into a Docker Image";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    supportedSystems = [ "x86_64-linux" ];
    # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
		nixPkgsFor = forAllSystems (system: import nixpkgs {
      inherit system;
      overlays = [
        (final: prev: {
          rWrapper = prev.rWrapper.override { packages = with prev.rPackages; [ 
						magrittr
						nanoparquet
						stringr
						dplyr
						purrr
						rlang
						tibble
						xml2
						qpdf
						pdftools
						devtools
						prev.poppler
					]; };
        })
      ];
    });
	in {
		packages = forAllSystems (system: let
			pkgs = nixPkgsFor.${system};
		in rec {
			default = pkgs.stdenv.mkDerivation {
				pname = "rtransparent";
				version = "1.0.0";
				src = [
					(builtins.path { name = "rtransparent"; path = ./R/.; })
				];
				buildPhase = ''
					runHook preBuild
					runHook postBuild
				'';

				installPhase = ''
					runHook preInstall
					
					mkdir -p $out/bin
					mkdir -p $out/lib
					cp $src/* $out/bin/.

					runHook postInstall
				'';
			};

			docker = pkgs.dockerTools.buildLayeredImage {
				name = "rtransparent";
				tag = "latest";
				contents = [ pkgs.bash default pkgs.rWrapper pkgs.coreutils ];
				config.WorkingDir = "${default}/bin";
				fakeRootCommands = ''
					R_LIBS=${default}/lib ${pkgs.rWrapper}/bin/R -e 'devtools::install_github("quest-bih/oddpub",ref="c5b091c7e82ed6177192dc380a515b3dc6304863")'
				'';
				config.Cmd = [ "${pkgs.rWrapper}/bin/Rscript" "${default}/bin/run.R" ];
				config.Env = [ "TMPDIR=/" "R_LIBS=${default}/lib" ];
			};

			singularity = pkgs.singularity-tools.buildImage {
				name = "rtransparent";
				singularity = pkgs.apptainer;
				contents = with pkgs; [ bash rWrapper coreutils default ];
				runAsRoot = ''
					#!${pkgs.bash}/bin/bash
					${pkgs.dockerTools.shadowSetup}
					mkdir -p /.singularity.d/env/

					echo "export TMPDIR=/" >> /.singularity.d/env/91-custom-environment.sh
				'';
				runScript = ''
					#!${pkgs.bash}/bin/bash
					cd ${default}/bin/
					${pkgs.rWrapper}/bin/Rscript ${default}/bin/run.R
				'';
			};
		});
  	};
}
