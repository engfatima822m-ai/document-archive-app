//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_twain_scanner/flutter_twain_scanner_plugin.h>
#include <printing/printing_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) flutter_twain_scanner_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlutterTwainScannerPlugin");
  flutter_twain_scanner_plugin_register_with_registrar(flutter_twain_scanner_registrar);
  g_autoptr(FlPluginRegistrar) printing_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "PrintingPlugin");
  printing_plugin_register_with_registrar(printing_registrar);
}
