#!/usr/bin/env bash
set -euo pipefail

# Install a source-only example; verify discovery in an unprivileged login shell.
(( EUID == 0 )) || { echo 'Run with sudo bash verify-no-paths.sh' >&2; exit 1; }
example=/opt/particle-stack/examples/all-components
install -d -m 0755 "$example"
cat > "$example/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.16)
project(all_components LANGUAGES CXX)
find_package(ROOT REQUIRED COMPONENTS Core Hist)
find_package(Geant4 REQUIRED)
find_package(Garfield REQUIRED)
include(${Geant4_USE_FILE})
add_executable(all-components main.cc)
target_compile_features(all-components PRIVATE cxx_std_17)
target_link_libraries(all-components PRIVATE
  Garfield::Garfield ${Geant4_LIBRARIES} ROOT::Core ROOT::Hist)
CMAKE
cat > "$example/main.cc" <<'CPP'
#include <iostream>
#include <TH1D.h>
#include <TROOT.h>
#include <Garfield/MediumMagboltz.hh>
#include <G4Material.hh>
#include <G4NistManager.hh>
#include <G4Version.hh>

int main() {
  gROOT->SetBatch(true);
  TH1D histogram("all_components", "", 10, 0., 10.);
  histogram.Fill(2.);
  if (histogram.GetEntries() != 1.) return 1;
  Garfield::MediumMagboltz gas;
  if (!gas.SetComposition("ar", 70., "co2", 30.)) return 2;
  const auto material = G4NistManager::Instance()->FindOrBuildMaterial("G4_Si");
  if (!material || !(material->GetDensity() > 0.)) return 3;
  std::cout << "ROOT " << gROOT->GetVersion() << '\n'
            << G4Version << '\n'
            << "Garfield++ Ar/CO2 composition: passed\n"
            << "ROOT histogram + Garfield++ gas + Geant4 material: passed\n";
}
CPP
chmod 0644 "$example/CMakeLists.txt" "$example/main.cc"

test_dir=$(mktemp -d /tmp/particle-stack-no-paths.XXXXXXXX)
trap 'rm -rf -- "$test_dir"' EXIT
install -d -m 0755 "$test_dir/home"
chown -R "$(id -u nobody):$(id -g nobody)" "$test_dir"

runuser -u nobody -- env -i \
  HOME="$test_dir/home" USER=nobody LOGNAME=nobody \
  PATH=/usr/local/bin:/usr/bin:/bin \
  /bin/bash -lc '
    set -euo pipefail
    [[ $(id -u) == "$(id -u nobody)" ]]
    cd "$HOME"
    echo "Unprivileged clean login: $(id -un)"
    command -v root root-config geant4-config cmake g++
    root-config --version
    geant4-config --version
    standard=$(root-config --cxxstandard)
    [[ $standard =~ ^(17|20|23)$ ]]
    source_dir=/opt/particle-stack/examples/all-components

    # No package-location overrides: use only the installed global environment.
    cmake -S "$source_dir" -B cmake-build \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD="$standard"
    cmake --build cmake-build -- -j"$(nproc)"
    ./cmake-build/all-components
    echo "CMake package discovery without prefix/directory flags: passed"

    # Explicit library names are required; include/library directories are global.
    g++ -std="c++$standard" "$source_dir/main.cc" -o manual-check \
      -lGarfield -lG4materials -lG4global -lCore -lHist
    ./manual-check
    echo "Manual g++ without -I/-L: passed"
  '
printf 'Source-only example installed: %s\n' "$example"
