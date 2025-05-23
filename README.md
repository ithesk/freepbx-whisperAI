# 🎙️ Transcriptor Automático FreePBX

Sistema automático de transcripción de llamadas para FreePBX usando OpenAI Whisper API. Monitorea nuevas grabaciones, extrae metadatos del archivo, transcribe automáticamente y envía por email con formato HTML profesional.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.8+](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/downloads/)
[![FreePBX](https://img.shields.io/badge/FreePBX-Compatible-green.svg)](https://www.freepbx.org/)

## 📋 características

- 🤖 **Monitoreo automático** de nuevas grabaciones en tiempo real
- 🔍 **Extracción inteligente de metadatos** del nombre del archivo FreePBX
- 🎙️ **Transcripción con OpenAI Whisper API** (rápida y precisa)
- 📧 **Envío automático por email** with formato HTML profesional
- 💾 **Guardado local** de transcripciones en archivos .txt
- 🛠️ **Scripts de gestión completos** para control del servicio
- 📊 **Logs detallados** para monitoreo y debugging
- 🔧 **Instalación automática** con un solo script

## 🚀 Instalación Rápida

### Requisitos previos:
- FreePBX instalado y funcionando
- Acceso root al servidor
- Conexión a internet
- Cuenta OpenAI con API key
- Cuenta Gmail con App Password configurada

### Instalación automática:
```bash
# Descargar el instalador
wget https://github.com/ithesk/freepbx-whisperAI/main/setup.sh

# Hacer ejecutable
chmod +x setup.sh

# Ejecutar como root
sudo ./setup.sh
```

El instalador automáticamente:
1. ✅ Verifica el sistema FreePBX
2. 📦 Instala todas las dependencias necesarias
3. 🔑 Te solicita las credenciales (OpenAI API key, Gmail)
4. 🤖 Crea y configura el transcriptor automático
5. 🧪 Prueba que todo funcione correctamente
6. 🛠️ Instala scripts de gestión

## ⚙️ Configuración

### OpenAI API Key:
1. Ve a [OpenAI API Keys](https://platform.openai.com/api-keys)
2. Crea una nueva API key
3. Copia la key (empieza con `sk-`)

### Gmail App Password:
1. Ve a [Google App Passwords](https://myaccount.google.com/apppasswords)
2. Activa verificación en 2 pasos (si no está activa)
3. Genera App Password para "Correo"
4. Copia la contraseña de 16 caracteres

## 🎯 Uso

### Comandos principales:
```bash
# Iniciar el transcriptor automático
freepbx-transcriptor start

# Ver estado del servicio
freepbx-transcriptor status

# Ver logs en tiempo real
freepbx-transcriptor logs

# Detener el servicio
freepbx-transcriptor stop

# Reiniciar el servicio
freepbx-transcriptor restart

# Probar configuración
freepbx-transcriptor test

# Editar configuración
freepbx-transcriptor config
```

### Instalar como servicio del sistema:
```bash
# Instalar como servicio systemd
freepbx-transcriptor install-service

# Iniciar servicio
systemctl start freepbx-transcriptor

# Habilitar inicio automático
systemctl enable freepbx-transcriptor

# Ver logs del servicio
journalctl -u freepbx-transcriptor -f
```

## 📞 Formatos de archivo soportados

El sistema extrae automáticamente metadatos de los nombres de archivo FreePBX:

### Formato completo:
```
external-2002-849000000-20250523-090937-1748005759.433.wav
    ↓
📥 Llamada entrante externa
📱 Extensión: 2002
📞 Caller: 8490000000
📅 Fecha: 23/05/2025 09:09:37
```

### Formatos soportados:
- `external-[ext]-[número]-[fecha]-[hora]-[timestamp].wav` - Llamadas externas entrantes
- `internal-[ext]-[número]-[fecha]-[hora]-[timestamp].wav` - Llamadas internas
- `in-[ext]-[número]-[timestamp].wav` - Llamadas entrantes (formato simple)
- `out-[ext]-[número]-[timestamp].wav` - Llamadas salientes (formato simple)

### Extensiones de audio compatibles:
- `.wav` (recomendado)
- `.mp3`
- `.m4a`  
- `.flac`

## 📧 Email automático

Cada transcripción se envía automáticamente por email con:

### Asunto automático:
```
📥 Llamada entrante externa - Ext 2002 - 23/05/2025 09:09:37
```

### Contenido HTML profesional:
- 📋 **Información detallada** de la llamada
- 📱 **Metadatos extraídos** (extensión, número, fecha, hora)
- 📊 **Estadísticas** (tamaño archivo, duración estimada)
- 📝 **Transcripción completa** con formato legible
- 🎨 **Diseño HTML responsive** para fácil lectura

## 🗂️ Estructura de archivos

```
/opt/freepbx-transcriptor/
├── transcriptor_automatico.py    # Script principal
├── freepbx-transcriptor          # Script de gestión
└── README.md                     # Documentación

/var/log/freepbx-transcriptor.log # Logs del sistema
/usr/local/bin/freepbx-transcriptor # Comando global
```

## 📝 Archivos de transcripción

Para cada grabación procesada se crea un archivo `.txt` con:

```
============================================================
TRANSCRIPCIÓN AUTOMÁTICA FREEPBX - OpenAI
============================================================

INFORMACIÓN DE LA LLAMADA:
- Archivo: external-2002-8493895277-20250523-090937-1748005759.433.wav
- Tipo: Llamada entrante externa
- Extensión: 2002
- Número Caller: 8493895277
- Fecha: 23/05/2025
- Hora: 09:09:37
- Timestamp: 1748005759.433
- Procesado: 23/05/2025 22:45:10
- Modelo: OpenAI whisper-1

============================================================
TRANSCRIPCIÓN:
============================================================

Buenos días, llamo para consultar sobre el estado de mi pedido...
```

## 💰 Costos

### OpenAI Whisper API:
- **$0.006 por minuto** de audio transcrito
- Ejemplos de costo:
  - 1 hora de audio = **$0.36**
  - 100 llamadas de 5 minutos = **$3.00**
  - 1000 llamadas de 3 minutos = **$18.00**

### Recomendaciones de costo:
- El sistema solo procesa archivos **mayores a 1KB**
- Archivos **mayores a 25MB se omiten** (límite de OpenAI)
- **No hay cargos** por archivos que no se pueden transcribir

## 🔧 Configuración avanzada

### Editar configuración manualmente:
```bash
sudo nano /opt/freepbx-transcriptor/transcriptor_automatico.py
```

### Parámetros configurables:
```python
# Modelo de Whisper (tiny, base, small, medium, large)
WHISPER_MODEL = "whisper-1"

# Idioma de transcripción
WHISPER_LANGUAGE = "es"  # español

# Tiempo de espera antes de procesar (segundos)
DELAY_PROCESAMIENTO = 30

# Carpeta de grabaciones FreePBX
CARPETA_GRABACIONES = "/var/spool/asterisk/monitor"
```

## 🐛 Troubleshooting

### El servicio no inicia:
```bash
# Verificar configuración
freepbx-transcriptor test

# Ver logs detallados
freepbx-transcriptor logs

# Verificar permisos
ls -la /opt/freepbx-transcriptor/
```

### Problemas de email:
```bash
# Probar conexión Gmail
python3 -c "
import smtplib, ssl
context = ssl.create_default_context()
with smtplib.SMTP('smtp.gmail.com', 587) as server:
    server.starttls(context=context)
    server.login('tu_email@gmail.com', 'tu_app_password')
print('✅ Gmail OK')
"
```

### Problemas con OpenAI:
```bash
# Probar API key
python3 -c "
from openai import OpenAI
client = OpenAI(api_key='tu-api-key')
models = client.models.list()
print('✅ OpenAI OK')
"
```

### Error de locks APT (durante instalación):
```bash
# Liberar locks
sudo pkill -f "apt|dpkg"
sudo rm -f /var/lib/apt/lists/lock
sudo rm -f /var/cache/apt/archives/lock
sudo dpkg --configure -a
```

## 📊 Logs y monitoreo

### Ver logs en tiempo real:
```bash
tail -f /var/log/freepbx-transcriptor.log
```

### Ejemplo de logs:
```
👁️ ARCHIVO DETECTADO: external-2002-8493895277-20250523-090937.wav
📂 Ruta: /var/spool/asterisk/monitor/2025/05/23
⏳ Esperando 30 segundos para procesar...

🚀 Iniciando procesamiento de: external-2002-8493895277-20250523-090937.wav
📁 Archivo: external-2002-8493895277-20250523-090937.wav
📥 Tipo: Llamada entrante externa
📱 Extensión: 2002
📞 Caller: 849000000
📅 Fecha: 23/05/2025 09:09:37

🎙️ Transcribiendo: external-2002-8493895277-20250523-090937.wav
✅ Transcripción completada: 145 caracteres
💾 Transcripción guardada: external-2002-8493895277-20250523-090937.txt
📧 Enviando email...
✅ ARCHIVO PROCESADO COMPLETAMENTE
```

## 🔒 Seguridad

### Archivos de configuración:
- Las credenciales se almacenan en `/opt/freepbx-transcriptor/transcriptor_automatico.py`
- Solo accesible por root
- Considera usar variables de entorno para producción

### Recomendaciones:
```bash
# Restringir permisos del archivo de configuración
sudo chmod 600 /opt/freepbx-transcriptor/transcriptor_automatico.py

# Crear usuario específico (opcional)
sudo useradd -r -s /bin/false freepbx-transcriptor
sudo chown freepbx-transcriptor:freepbx-transcriptor /opt/freepbx-transcriptor/
```

## 🤝 Contribuir

1. Fork el proyecto
2. Crea una rama para tu feature (`git checkout -b feature/AmazingFeature`)
3. Commit tus cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abre un Pull Request

## 📜 Changelog

### v1.0.0 (2025-05-23)
- ✅ Monitoreo automático de archivos
- ✅ Extracción de metadatos FreePBX
- ✅ Integración OpenAI Whisper API
- ✅ Envío automático por email HTML
- ✅ Scripts de gestión completos
- ✅ Instalador automático

## ❓ FAQ

### ¿Funciona con todas las versiones de FreePBX?
Sí, el sistema monitorea la carpeta estándar `/var/spool/asterisk/monitor` que es compatible con todas las versiones.

### ¿Puedo usar otros modelos de Whisper?
Sí, puedes cambiar `WHISPER_MODEL` en la configuración. Modelos disponibles: `whisper-1`.

### ¿Qué pasa si se cae el servicio?
El sistema incluye reinicio automático. También puedes configurarlo como servicio systemd para mayor confiabilidad.

### ¿Puedo procesar archivos existentes?
El sistema procesa automáticamente archivos nuevos. Para archivos existentes, puedes moverlos temporalmente para que sean detectados como nuevos.

### ¿Funciona con múltiples idiomas?
Sí, cambia `WHISPER_LANGUAGE` en la configuración. OpenAI Whisper soporta más de 50 idiomas.

## 📞 Soporte

- 🐛 **Issues**: [GitHub Issues] (https://github.com/ithesk/freepbx-whisperAI/issues)
- 📧 **Email**: info@mo35.dev
- 📚 **Documentación**: [Wiki del proyecto] (https://github.com/ithesk/freepbx-whisperAI/wiki)

## 📄 Licencia

Este proyecto está licenciado bajo la Licencia MIT - ver el archivo [LICENSE](LICENSE) para detalles.

## 🙏 Agradecimientos

- [OpenAI](https://openai.com/) por la API de Whisper
- [FreePBX](https://www.freepbx.org/) por la plataforma de telefonía
- Comunidad de código abierto por las librerías utilizadas

---

⭐ **¡Si este proyecto te ayuda, considera darle una estrella!** ⭐
