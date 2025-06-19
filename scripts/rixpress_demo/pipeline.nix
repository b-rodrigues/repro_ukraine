let
  default = import ./default.nix;
  defaultPkgs = default.pkgs;
  defaultShell = default.shell;
  defaultBuildInputs = defaultShell.buildInputs;
  defaultConfigurePhase = ''
    cp ${./_rixpress/default_libraries.py} libraries.py
    cp ${./_rixpress/default_libraries.R} libraries.R
    mkdir -p $out  
    mkdir -p .julia_depot  
    export JULIA_DEPOT_PATH=$PWD/.julia_depot  
    export HOME_PATH=$PWD
  '';
  
  # Function to create R derivations
  makeRDerivation = { name, buildInputs, configurePhase, buildPhase, src ? null }:
    defaultPkgs.stdenv.mkDerivation {
      inherit name src;
      dontUnpack = true;
      inherit buildInputs configurePhase buildPhase;
      installPhase = ''
        cp ${name} $out/
      '';
    };
  # Function to create Python derivations
  makePyDerivation = { name, buildInputs, configurePhase, buildPhase, src ? null }:
    let
      pickleFile = "${name}";
    in
      defaultPkgs.stdenv.mkDerivation {
        inherit name src;
        dontUnpack = true;
        buildInputs = buildInputs;
        inherit configurePhase buildPhase;
        installPhase = ''
          cp ${pickleFile} $out
        '';
      };

  # Define all derivations
    mtcars_pl = makePyDerivation {
    name = "mtcars_pl";
    src = ./data/mtcars.csv;
    buildInputs = defaultBuildInputs;
    configurePhase = defaultConfigurePhase;
    buildPhase = ''
      cp $src input_file
python -c "
exec(open('libraries.py').read())
file_path = 'input_file'
data = eval('lambda x: polars.read_csv(x, separator=\'|\')')(file_path)
with open('mtcars_pl', 'wb') as f:
    pickle.dump(data, f)
"

    '';
  };

  mtcars_pl_am = makePyDerivation {
    name = "mtcars_pl_am";
    buildInputs = defaultBuildInputs;
    configurePhase = defaultConfigurePhase;
    buildPhase = ''
      python -c "
exec(open('libraries.py').read())
with open('${mtcars_pl}/mtcars_pl', 'rb') as f: mtcars_pl = pickle.load(f)
exec('mtcars_pl_am = mtcars_pl.filter(polars.col(\'am\') == 0)')
write_to_csv(globals()['mtcars_pl_am'], 'mtcars_pl_am')
"
    '';
  };

  mtcars_head = makeRDerivation {
    name = "mtcars_head";
    buildInputs = defaultBuildInputs;
    configurePhase = defaultConfigurePhase;
    buildPhase = ''
      Rscript -e "
        source('libraries.R')
        mtcars_pl_am <- "read.csv"('${mtcars_pl_am}/mtcars_pl_am')
        mtcars_head <- my_head(mtcars_pl_am)
        "my_write.csv"(mtcars_head, 'mtcars_head')"
    '';
  };

  mtcars_tail_py = makePyDerivation {
    name = "mtcars_tail_py";
    buildInputs = defaultBuildInputs;
    configurePhase = defaultConfigurePhase;
    buildPhase = ''
      python -c "
exec(open('libraries.py').read())
mtcars_head = read_from_csv('${mtcars_head}/mtcars_head')
exec('mtcars_tail_py = mtcars_head.tail()')
write_to_csv(globals()['mtcars_tail_py'], 'mtcars_tail_py')
"
    '';
  };

  mtcars_mpg = makeRDerivation {
    name = "mtcars_mpg";
    buildInputs = defaultBuildInputs;
    configurePhase = defaultConfigurePhase;
    buildPhase = ''
      Rscript -e "
        source('libraries.R')
        mtcars_tail_py <- "read.csv"('${mtcars_tail_py}/mtcars_tail_py')
        mtcars_mpg <- dplyr::select(mtcars_tail_py, mpg)
        saveRDS(mtcars_mpg, 'mtcars_mpg')"
    '';
  };

  page = defaultPkgs.stdenv.mkDerivation {
    name = "page";
    src = defaultPkgs.lib.fileset.toSource {
      root = ./.;
      fileset = defaultPkgs.lib.fileset.unions [ ./my_doc/page.qmd ./my_doc/content.qmd ./my_doc/images ];
    };
    buildInputs = defaultBuildInputs;
    configurePhase = defaultConfigurePhase;
    buildPhase = ''
      mkdir home
      export HOME=$PWD/home
      export RETICULATE_PYTHON=${defaultPkgs.python3}/bin/python

      substituteInPlace my_doc/page.qmd --replace-fail 'rxp_read("mtcars_head")' 'rxp_read("${mtcars_head}")'
      substituteInPlace my_doc/page.qmd --replace-fail 'rxp_read("mtcars_mpg")' 'rxp_read("${mtcars_mpg}")'
      substituteInPlace my_doc/page.qmd --replace-fail 'rxp_read("mtcars_pl")' 'rxp_read("${mtcars_pl}")'
      quarto render my_doc/page.qmd  --output-dir $out
    '';
  };

  # Generic default target that builds all derivations
  allDerivations = defaultPkgs.symlinkJoin {
    name = "all-derivations";
    paths = with builtins; attrValues { inherit mtcars_pl mtcars_pl_am mtcars_head mtcars_tail_py mtcars_mpg page; };
  };

in
{
  inherit mtcars_pl mtcars_pl_am mtcars_head mtcars_tail_py mtcars_mpg page;
  default = allDerivations;
}
