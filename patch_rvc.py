"""Se ejecuta al construir la imagen.

rvc-python, cada vez que arranca en CPU, reescribe sus propios archivos de
configuración dentro de site-packages. Con un contenedor de solo lectura y sin
root eso falla. Aquí aplicamos esos cambios una sola vez y quitamos la escritura.
"""
import os
import rvc_python

lib = os.path.dirname(rvc_python.__file__)
cfg_py = os.path.join(lib, "configs", "config.py")

# 1) Aplicar una vez lo que haría use_fp32_config()
for name in ["v1/32k.json", "v1/40k.json", "v1/48k.json", "v2/48k.json", "v2/32k.json"]:
    p = os.path.join(lib, "configs", name)
    with open(p) as f:
        data = f.read().replace("true", "false")
    with open(p, "w") as f:
        f.write(data)
pre = os.path.join(lib, "modules", "train", "preprocess.py")
with open(pre) as f:
    data = f.read().replace("3.7", "3.0")
with open(pre, "w") as f:
    f.write(data)

# 2) Dejar use_fp32_config() solo en memoria (sin escribir a disco)
src = open(cfg_py).read()
marker = "    def use_fp32_config(self):\n"
if marker not in src:
    raise SystemExit("rvc-python cambió: revisar patch_rvc.py")
src = src.replace(marker, marker +
    "        for config_file in version_config_list:\n"
    "            self.json_config[config_file]['train']['fp16_run'] = False\n"
    "        return\n", 1)
open(cfg_py, "w").write(src)
# 3) Carga SEGURA de los modelos de voz (.pth que puede añadir cualquiera):
#    weights_only=True solo acepta tensores y datos simples, nunca código.
mod = os.path.join(lib, "modules", "vc", "modules.py")
src = open(mod).read()
viejo = 'self.cpt = torch.load(sid, map_location="cpu")'
if viejo not in src:
    raise SystemExit("rvc-python cambió (modules.py): revisar patch_rvc.py")
open(mod, "w").write(src.replace(viejo, 'self.cpt = torch.load(sid, map_location="cpu", weights_only=True)'))

# 4) HuBERT (modelo base de fairseq) necesita weights_only=False. Es seguro porque
#    ese archivo se verifica por SHA-256 al construir la imagen y nadie lo puede cambiar.
import fairseq  # noqa: E402

cu = os.path.join(os.path.dirname(fairseq.__file__), "checkpoint_utils.py")
src = open(cu).read()
viejo = 'state = torch.load(f, map_location=torch.device("cpu"))'
if viejo not in src:
    raise SystemExit("fairseq cambió (checkpoint_utils.py): revisar patch_rvc.py")
open(cu, "w").write(src.replace(viejo, 'state = torch.load(f, map_location=torch.device("cpu"), weights_only=False)'))
print("rvc-python parcheado: solo lectura + carga segura de modelos")
