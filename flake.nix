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
					cp $src/* $out/bin/.

					runHook postInstall
				'';
			};

			docker = pkgs.dockerTools.buildImage {
				name = "rtransparent";
				tag = "latest";
				copyToRoot = buildEnv {
					name = "image-root";
					paths = with pkgs; [ bash default rWrapper coreutils cacert ];
					pathsToLink = [ "/bin" ];
				};

				extraCommands = ''
					mkdir -p /R/lib
					R_LIBS=/R/lib ${pkgs.rWrapper}/bin/R -e 'devtools::install_github("quest-bih/oddpub",ref="c5b091c7e82ed6177192dc380a515b3dc6304863")'
				'';
				config.WorkingDir = "${default}/bin";
				config.Cmd = [ "${pkgs.rWrapper}/bin/Rscript" "${default}/bin/run.R" ];
				config.Env = [ "TMPDIR=/" "R_LIBS=/R/lib" ];
			};
		});
  	};
}
