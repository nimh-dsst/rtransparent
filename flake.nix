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
					oddpub = prev.rPackages.buildRPackage {
						name = "oddpub";
						src = prev.fetchFromGitHub {
							owner = "quest-bih";
							repo = "oddpub";
							rev = "c5b091c7e82ed6177192dc380a515b3dc6304863";
							sha256 = "PB+gf09iU5uCrzKXnmhzI7eL1bhhXtRfjK5VfuAqq3o=";
						};
						buildInputs = with prev.rPackages; [
							dplyr purrr foreach doParallel tokenizers stringr magrittr readr
							prev.rWrapper
						];
					};

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
						prev.poppler
						final.oddpub
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
				copyToRoot = pkgs.buildEnv {
					name = "image-root";
					paths = with pkgs; [ bash default rWrapper coreutils ];
					pathsToLink = [ "/bin" ];
				};

				config.WorkingDir = "${default}/bin";
				config.Cmd = [ "${pkgs.rWrapper}/bin/Rscript" "${default}/bin/run.R" ];
				config.Env = [ "TMPDIR=/" ];
			};

			devShell = (pkgs.buildFHSEnv {
				name = "shell-env";
				targetPkgs = _: [ rWrapper ];
			}).env;
		});
  	};
}
