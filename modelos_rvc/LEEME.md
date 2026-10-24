# Modelos de voz (RVC)

Cada carpeta aquí dentro es una voz. Necesita:

- un archivo `.pth` (el modelo, obligatorio)
- un archivo `.index` (opcional, mejora el parecido)
- un `voz.json` (opcional: nombre, descripción y ajustes)

Los `.pth` / `.index` de las voces incluidas los instala `bash descargar_modelos.sh`
desde los *Releases* del repo (son muy grandes para guardarlos en git).

## Añadir tu propia voz

1. Crea una carpeta, p. ej. `modelos_rvc/mi_voz/`
2. Mete dentro su `.pth` (y su `.index` si lo tiene)
3. (Opcional) copia un `voz.json` de otra carpeta y cambia el nombre
4. Reinicia: `bash detener.sh && bash iniciar.sh`

Ajustes de `voz.json`:

| Campo | Qué hace |
| --- | --- |
| `base_voice` | Voz de edge-tts que se usa antes de clonar (`es-MX-JorgeNeural`, `es-CO-GonzaloNeural`, `es-ES-AlvaroNeural`, voces femeninas como `es-MX-DaliaNeural`…) |
| `f0up_key` | Semitonos: `+12` para voz femenina a partir de una masculina, `-12` al revés |
| `index_rate` | 0–1. Más alto = más parecido al modelo (y más acento del original) |
| `protect` | 0–0.5. Protege consonantes/respiraciones |
