## Qué cambia y por qué
<!-- Una o dos frases. Enlaza el issue si existe: Closes #123 -->

## Tipo de cambio
- [ ] Corrección (patch)
- [ ] Función nueva compatible (minor)
- [ ] Cambio que rompe compatibilidad (major)
- [ ] Seguridad
- [ ] Documentación / CI

## Lista de comprobación
- [ ] `python3 -m unittest discover -s tests` y `bash tests/test_statusline.sh` pasan en local
- [ ] He añadido o ajustado pruebas si toco el servidor o el instalador
- [ ] He añadido una línea en `CHANGELOG.md` bajo `[Sin publicar]` (con **[seguridad]** si procede)
- [ ] No añado dependencias externas
- [ ] No hay secretos, tokens ni rutas personales en el diff
- [ ] Si toco `diffserver.py`: siguen dando 403 las peticiones sin token y con `Host` ajeno

## Cómo lo has probado
<!-- Sistema operativo, terminal, versión de Claude Code -->
