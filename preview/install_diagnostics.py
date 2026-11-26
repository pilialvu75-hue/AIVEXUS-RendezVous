"""Install the exact reviewed Diagnostics module into the generated RV host."""
from pathlib import Path
import re
import subprocess
import sys

PIN = "e641390200a734a60cd1eac2759207e9431f2dd2"
generated = Path(sys.argv[1]).resolve()
library = Path(sys.argv[2]).resolve()
actual = subprocess.check_output(["git", "-C", str(library), "rev-parse", "HEAD"], text=True).strip()
if actual != PIN:
    raise RuntimeError("Diagnostics commit mismatch")
package = library / "packages/aivexus_original_diagnostics"
pub = generated / "pubspec.yaml"
s = pub.read_text(encoding="utf-8")
if s.count("\ndependencies:") != 1 or "aivexus_original_diagnostics:" in s:
    raise RuntimeError("Unexpected dependencies")
s = s.replace("\ndependencies:", """\ndependencies:
  flutter_localizations:
    sdk: flutter
  aivexus_original_diagnostics:
    git:
      url: https://github.com/pilialvu75-hue/AI-Orchestrator-Module-Library.git
      ref: e641390200a734a60cd1eac2759207e9431f2dd2
      path: packages/aivexus_original_diagnostics""", 1)
pub.write_text(s, encoding="utf-8")
kotlin = generated / "android/app/src/main/kotlin/com/aivexus/rendezvous"
for name in ("ResourceTelemetry", "ProcessExitDiagnostics"):
    source = package / "host-adapters/android" / f"{name}.kt.template"
    target = kotlin / f"{name}.kt"
    if target.exists():
        raise RuntimeError("Refusing to overwrite native adapter")
    target.write_text(source.read_text(encoding="utf-8").replace("__ANDROID_NAMESPACE__", "com.aivexus.rendezvous"), encoding="utf-8")
p = kotlin / "MainActivity.kt"
s = p.read_text(encoding="utf-8")
if "cleanUpFlutterEngine" in s:
    raise RuntimeError("Existing lifecycle hook requires review")
m = list(re.finditer(r"override fun configureFlutterEngine\(\s*(\w+):\s*FlutterEngine\s*\)\s*\{", s))
if len(m) != 1:
    raise RuntimeError("Unexpected native host registration")
engine = m[0].group(1)
needle = f"super.configureFlutterEngine({engine})"
if s.count(needle) != 1:
    raise RuntimeError("Unexpected super call")
s = s[:m[0].start()] + """private var diagnosticsResources: ResourceTelemetry? = null
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        diagnosticsResources?.close()
        diagnosticsResources = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
    """ + s[m[0].start():]
s = s.replace(needle, needle + f"""
        diagnosticsResources?.close()
        diagnosticsResources = ResourceTelemetry(applicationContext, {engine})
        ProcessExitDiagnostics.register(applicationContext, {engine})""", 1)
p.write_text(s, encoding="utf-8")
print("Pinned Diagnostics integrated; package identity, WebView and OTA channels unchanged.")
