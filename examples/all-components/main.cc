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
