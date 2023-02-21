# https://github.com/CnTeng/nixfiles/blob/9978780680da184285ab662297de563b49d39e05/pkgs/caddy-with-plugins/default.nix

# Copy https://github.com/NixOS/nixpkgs/pull/191883#issuecomment-1250652290
# & https://github.com/NixOS/nixpkgs/issues/14671
{ fetchFromGitHub, buildGoModule, stdenv, installShellFiles, go, srcOnly }:
let
  version = "2.6.2";
  caddySrc = srcOnly (fetchFromGitHub {
    owner = "caddyserver";
    repo = "caddy";
    rev = "v${version}";
    hash = "sha256-Tbf6RB3106OEZGc/Wx7vk+I82Z8/Q3WqnID4f8uZ6z0=";
  });# Clone from https://github.com/caddyserver/caddy

  dist = fetchFromGitHub {
    owner = "caddyserver";
    repo = "dist";
    rev = "v${version}";
    sha256 = "sha256-EXs+LNb87RWkmSWvs8nZIVqRJMutn+ntR241gqI7CUg=";
  };

  cgiSrc = srcOnly (fetchFromGitHub {
    owner = "aksdb";
    repo = "caddy-cgi";
    rev = "v2.2.0";
    hash = "sha256-o8yPvW5+Vy9vMufWI/3xtVrW0EuTnMIeJPGMAOuCf2c=";
  });

  ratelimitSrc = srcOnly (fetchFromGitHub {
    owner = "RussellLuo";
    repo = "caddy-ext";
    rev = "ratelimit/v0.2.0";
    hash = "sha256-1JSO+CPQBu08pGIsbIVX2SSXTPISv3aBA27W2xAorWM=";
  });

  cacheSrc = srcOnly (fetchFromGitHub {
    owner = "caddyserver";
    repo = "cache-handler";
    rev = "v0.4.0";
    hash = "sha256-c9SzZh+7S2mXcw9RdmGcg11YyCTMUM/l+Wc/v8uBjnk=";
  });

  combinedSrc = stdenv.mkDerivation {
    name = "caddy-src";

    nativeBuildInputs = [ go ];

    buildCommand = ''
      export GOCACHE="$TMPDIR/go-cache"
      export GOPATH="$TMPDIR/go"

      mkdir -p "$out/caddywithplugins"
      cp -r ${caddySrc} "$out/caddy"
      cp -r ${cgiSrc} "$out/cgi"
      cp -r ${ratelimitSrc}/ratelimit "$out/ratelimit"
      cp -r ${cacheSrc} "$out/cache"

      cd "$out/caddywithplugins"
      go mod init caddy
      echo "package main" >> main.go
      echo 'import caddycmd "github.com/caddyserver/caddy/v2/cmd"' >> main.go
      echo 'import _ "github.com/caddyserver/caddy/v2/modules/standard"' >> main.go
      echo 'import _ "github.com/aksdb/caddy-cgi/v2"' >> main.go
      echo 'import _ "github.com/RussellLuo/caddy-ext/ratelimit"' >> main.go
      echo 'import _ "github.com/caddyserver/cache-handler"' >> main.go

      echo "func main(){ caddycmd.Main() }" >> main.go

      go mod edit -require=github.com/caddyserver/caddy/v2@v2.6.2
      go mod edit -replace github.com/caddyserver/caddy/v2=../caddy

      go mod edit -require=github.com/aksdb/caddy-cgi/v2@v2.2.0
      go mod edit -replace github.com/aksdb/caddy-cgi/v2=../cgi

      go mod edit -require=github.com/RussellLuo/caddy-ext/ratelimit@v0.2.0
      go mod edit -replace github.com/RussellLuo/caddy-ext/ratelimit=../ratelimit

      go mod edit -require=github.com/caddyserver/cache-handler@v0.4.0
      go mod edit -replace github.com/caddyserver/cache-handler=../cache
    '';
  };
in
buildGoModule {
  name = "caddy-with-plugins";

  src = combinedSrc;

  vendorHash = "sha256-9z2B93ss8tacei+66hZFp8L/flt1QnUKAiTon21Hpfw=";

  overrideModAttrs = _: {
    postPatch = "cd caddywithplugins";

    postConfigure = ''
      go mod tidy
    '';

    postInstall = ''
      mkdir -p "$out/.magic"
      cp go.mod go.sum "$out/.magic"
    '';
  };

  #nativeBuildInputs = [ installShellFiles ];
  #postInstall = ''
  #  echo $out
  #  install -Dm644 ${dist}/init/caddy.service ${dist}/init/caddy-api.service -t $out/lib/systemd/system

  #  substituteInPlace $out/lib/systemd/system/caddy.service --replace "/usr/bin/caddy" "$out/bin/caddy"
  #  substituteInPlace $out/lib/systemd/system/caddy-api.service --replace "/usr/bin/caddy" "$out/bin/caddy"

  #  installShellCompletion --cmd metal \
  #    --bash <($out/bin/caddy completion bash) \
  #    --zsh <($out/bin/caddy completion zsh)
  #'';

  postPatch = "cd caddywithplugins";

  postConfigure = ''
    cp vendor/.magic/go.* .
  '';
}
