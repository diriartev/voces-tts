"""Se ejecuta DENTRO de la imagen: comprueba que un .pth malicioso no puede ejecutar código."""
import io
import os
import pickle
import sys
import zipfile

import torch

import rvc_python

MARCA = "/tmp/pwned_prueba"  # noqa: S108 - tmpfs desechable del contenedor de prueba


class Exploit:
    def __reduce__(self):
        return (os.system, (f"touch {MARCA}",))


buf = io.BytesIO()
with zipfile.ZipFile(buf, "w") as z:
    z.writestr("archive/data.pkl", pickle.dumps({"weight": Exploit()}, protocol=2))
    z.writestr("archive/version", "3\n")
buf.seek(0)

fallos = 0
mod = os.path.join(os.path.dirname(rvc_python.__file__), "modules", "vc", "modules.py")
with open(mod) as f:
    if 'torch.load(sid, map_location="cpu", weights_only=True)' in f.read():
        print("  ✔ rvc-python carga los modelos de voz con weights_only=True")
    else:
        print("  ✘ rvc-python NO usa carga segura")
        fallos += 1

try:
    torch.load(buf, map_location="cpu", weights_only=True)
    print("  ✘ torch cargó un modelo malicioso")
    fallos += 1
except Exception:
    print("  ✔ torch rechaza un .pth malicioso")

if os.path.exists(MARCA):
    print("  ✘ ¡el código malicioso llegó a ejecutarse!")
    fallos += 1
else:
    print("  ✔ el código malicioso no se ejecutó")

sys.exit(1 if fallos else 0)
