{
  description = "Packaging RTransparent into a Docker Image";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    supportedSystems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];
    # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
		nixPkgsFor = forAllSystems (system: import nixpkgs {
      inherit system;
      overlays = [
        (final: prev: {
          rWrapper = prev.rWrapper.override { packages = with prev.rPackages; [ 
						magrittr
						stringr
						dplyr
						purrr
						rlang
						tibble
						xml2
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

			docker = pkgs.dockerTools.buildLayeredImage {
				name = "rtransparent";
				tag = "latest";
				contents = [ pkgs.bash default pkgs.rWrapper ];
				config.WorkingDir = "${default}/bin";
				config.Cmd = [ "${pkgs.rWrapper}/bin/Rscript" "${default}/bin/run.R" ];
			};
		});
  	};
}
