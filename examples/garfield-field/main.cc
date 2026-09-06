#include <cmath>
#include <iostream>
#include <string>
#include <TApplication.h>
#include <TCanvas.h>
#include <TROOT.h>
#include <TTimer.h>
#include <Garfield/ComponentAnalyticField.hh>
#include <Garfield/MediumMagboltz.hh>
#include <Garfield/ViewField.hh>

int main(int argc, char* argv[]) {
  const std::string mode = argc == 2 ? argv[1] : "--batch";
  if (argc > 2 || (mode != "--batch" && mode != "--gui" && mode != "--gui-smoke")) {
    std::cerr << "Usage: garfield-field [--batch|--gui|--gui-smoke]\n";
    return 2;
  }
  const bool gui = mode != "--batch";
  gROOT->SetBatch(!gui);
  // Keep our command-line options away from ROOT's own option parser.
  int rootArgc = 1;
  char* rootArgv[] = {argv[0], nullptr};
  TApplication app("garfield-field", &rootArgc, rootArgv);
  if (gui && gROOT->IsBatch()) {
    std::cerr << "No GUI display available. Check WSLg and DISPLAY.\n";
    return 3;
  }

  Garfield::MediumMagboltz gas;
  if (!gas.SetComposition("ar", 70., "co2", 30.)) return 4;
  Garfield::ComponentAnalyticField field;
  field.SetMedium(&gas);
  // Garfield lengths are cm; these planes are 2 mm apart.
  field.AddPlaneY(-0.1, -1000., "cathode");
  field.AddPlaneY(0.1, 0., "anode");
  double ex = 0., ey = 0., ez = 0., potential = 0.;
  Garfield::Medium* medium = nullptr;
  int status = 0;
  field.ElectricField(0., 0., 0., ex, ey, ez, potential, medium, status);
  // Analytic reference: E_y = -dV/dy = -5000 V/cm, V(0) = -500 V.
  if (status != 0 || medium != &gas || !std::isfinite(ey) ||
      std::abs(ex) > 1.e-6 || std::abs(ez) > 1.e-6 ||
      std::abs(ey + 5000.) > 1.e-6 || std::abs(potential + 500.) > 1.e-6) {
    std::cerr << "Uniform-field check failed: status=" << status << '\n';
    return 5;
  }
  std::cout << "Uniform-field check passed: Ey=" << ey
            << " V/cm, V=" << potential << " V\n";
  if (!gui) return 0;

  TCanvas canvas("field_canvas", "Garfield++: parallel-plate potential", 900, 650);
  Garfield::ViewField view(&field);
  view.SetCanvas(&canvas);
  view.SetPlane(0., 0., 1., 0., 0., 0.);
  view.SetArea(-0.1, -0.099, 0.1, 0.099);
  view.Plot("v", "colz");
  canvas.Update();
  if (!canvas.GetWindowWidth()) return 6;
  canvas.Connect("Closed()", "TApplication", &app, "Terminate()");
  if (mode == "--gui-smoke") {
    TTimer::SingleShot(2500, "TApplication", &app, "Terminate()");
  }
  std::cout << "GUI ready. Close the canvas to exit.\n";
  app.Run(true);
  return 0;
}
