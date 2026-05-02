//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_twain_scanner/flutter_twain_scanner_plugin_c_api.h>
#include <printing/printing_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FlutterTwainScannerPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterTwainScannerPluginCApi"));
  PrintingPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PrintingPlugin"));
}
