#!/bin/bash

# =========================================================================
# INSTALADOR COMPLETO - TRANSCRIPTOR AUTOMÁTICO FREEPBX CON POCKETBASE
# Instala y configura todo automáticamente + Integración PocketBase
# =========================================================================

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Funciones de logging
log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅ $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] ℹ️  $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ❌ $1${NC}"
}

header() {
    echo -e "${PURPLE}$1${NC}"
}

# Banner inicial
clear
header "
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   🎙️  INSTALADOR AUTOMÁTICO TRANSCRIPTOR FREEPBX            ║
║                   🗄️  CON POCKETBASE                        ║
║                                                               ║
║   • Instalación completa automática                          ║
║   • Configuración de OpenAI API                              ║
║   • Configuración de Gmail                                   ║
║   • Integración con PocketBase                               ║
║   • Monitoreo automático de grabaciones                      ║
║   • Transcripción y almacenamiento en BD                     ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
"

echo -e "${WHITE}Preparando instalación...${NC}"
sleep 2

# Variables globales
INSTALL_DIR="/opt/freepbx-transcriptor"
OPENAI_API_KEY=""
EMAIL_USUARIO=""
EMAIL_PASSWORD=""
EMAIL_DESTINO=""
POCKETBASE_URL=""
POCKETBASE_EMAIL=""
POCKETBASE_PASSWORD=""

# =========================================================================
# FUNCIONES DE INSTALACIÓN
# =========================================================================

verificar_sistema() {
    header "🔍 VERIFICANDO SISTEMA"
    
    # Verificar que somos root
    if [ "$EUID" -ne 0 ]; then
        error "Este script debe ejecutarse como root"
        echo "Ejecuta: sudo $0"
        exit 1
    fi
    
    # Verificar FreePBX
    if [ ! -d "/var/spool/asterisk/monitor" ]; then
        error "No se encontró FreePBX. Carpeta /var/spool/asterisk/monitor no existe"
        exit 1
    fi
    
    log "FreePBX detectado correctamente"
    
    # Detectar distribución
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        info "Sistema detectado: $OS $VER"
    else
        warning "No se pudo detectar la distribución, continuando..."
    fi
    
    # Verificar Python
    if ! command -v python3 &> /dev/null; then
        error "Python3 no está instalado"
        exit 1
    fi
    
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    log "Python3 detectado: $PYTHON_VERSION"
    
    # Verificar conexión a internet
    if ! ping -c 1 google.com &> /dev/null; then
        error "No hay conexión a internet"
        exit 1
    fi
    
    log "Conexión a internet verificada"
}

instalar_dependencias() {
    header "📦 INSTALANDO DEPENDENCIAS DEL SISTEMA"
    
    # Función para manejar locks de APT
    esperar_apt_lock() {
        local max_intentos=10
        local intento=1
        
        while [ $intento -le $max_intentos ]; do
            if fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
                warning "APT está bloqueado, esperando... (intento $intento/$max_intentos)"
                sleep 10
            else
                break
            fi
            ((intento++))
        done
        
        if [ $intento -gt $max_intentos ]; then
            warning "APT sigue bloqueado, liberando locks..."
            pkill -f "apt|dpkg" 2>/dev/null || true
            sleep 3
            rm -f /var/lib/apt/lists/lock 2>/dev/null || true
            rm -f /var/cache/apt/archives/lock 2>/dev/null || true
            rm -f /var/lib/dpkg/lock* 2>/dev/null || true
            dpkg --configure -a 2>/dev/null || true
            log "Locks liberados"
        fi
    }
    
    # Detectar gestor de paquetes e instalar
    if command -v apt &> /dev/null; then
        info "Usando APT (Debian/Ubuntu)"
        
        # Esperar y liberar locks si es necesario
        esperar_apt_lock
        
        # Actualizar con reintentos
        for intento in {1..3}; do
            if apt update -qq; then
                break
            else
                warning "Reintentando apt update... ($intento/3)"
                esperar_apt_lock
            fi
        done
        
        # Instalar paquetes con reintentos
        for intento in {1..3}; do
            if apt install -y python3 python3-pip python3-venv python3-full python3-dev \
                              build-essential curl wget git nano; then
                break
            else
                warning "Reintentando instalación de paquetes... ($intento/3)"
                esperar_apt_lock
            fi
        done
        
        # Instalar paquetes Python (incluyendo requests para PocketBase)
        log "Instalando paquetes Python..."
        if ! pip3 install --break-system-packages --user openai watchdog requests pydub 2>/dev/null; then
            warning "Probando método alternativo para pip..."
            pip3 install --user openai watchdog requests pydub 2>/dev/null || {
                python3 -m pip install --user openai watchdog requests pydub
            }
        fi
        
    elif command -v yum &> /dev/null; then
        info "Usando YUM (CentOS/RHEL)"
        yum update -y
        yum install -y python3 python3-pip python3-devel gcc gcc-c++ \
                       curl wget git nano
        pip3 install --user openai watchdog requests pydub
        
    elif command -v dnf &> /dev/null; then
        info "Usando DNF (Fedora)"
        dnf update -y
        dnf install -y python3 python3-pip python3-devel gcc gcc-c++ \
                       curl wget git nano
        pip3 install --user openai watchdog requests pydub
        
    else
        error "Gestor de paquetes no soportado"
        exit 1
    fi
    
    log "Dependencias instaladas correctamente"
}

configurar_credenciales() {
    header "🔑 CONFIGURACIÓN DE CREDENCIALES"
    
    echo -e "${CYAN}Necesitamos configurar las credenciales para el servicio:${NC}"
    echo
    
    # OpenAI API Key
    while [ -z "$OPENAI_API_KEY" ]; do
        echo -e "${YELLOW}1. API Key de OpenAI:${NC}"
        echo "   • Ve a: https://platform.openai.com/api-keys"
        echo "   • Crea una nueva API key"
        echo "   • Copia la key (empieza con 'sk-')"
        echo
        read -p "Ingresa tu OpenAI API Key: " OPENAI_API_KEY
        
        if [[ ! $OPENAI_API_KEY =~ ^sk- ]]; then
            error "La API key debe empezar con 'sk-'"
            OPENAI_API_KEY=""
        fi
    done
    
    # Email de Gmail
    while [ -z "$EMAIL_USUARIO" ]; do
        echo -e "${YELLOW}2. Email de Gmail (origen):${NC}"
        read -p "Ingresa tu email de Gmail: " EMAIL_USUARIO
        
        if [[ ! $EMAIL_USUARIO =~ @gmail\.com$ ]]; then
            error "Debe ser un email de Gmail (@gmail.com)"
            EMAIL_USUARIO=""
        fi
    done
    
    # App Password de Gmail
    while [ -z "$EMAIL_PASSWORD" ]; do
        echo -e "${YELLOW}3. App Password de Gmail:${NC}"
        echo "   • Ve a: https://myaccount.google.com/apppasswords"
        echo "   • Activa verificación en 2 pasos (si no está activa)"
        echo "   • Genera App Password para 'Correo'"
        echo "   • Copia la contraseña de 16 caracteres"
        echo
        read -p "Ingresa tu App Password (16 caracteres): " EMAIL_PASSWORD
        
        # Remover espacios
        EMAIL_PASSWORD=$(echo $EMAIL_PASSWORD | tr -d ' ')
        
        if [ ${#EMAIL_PASSWORD} -ne 16 ]; then
            error "El App Password debe tener exactamente 16 caracteres"
            EMAIL_PASSWORD=""
        fi
    done
    
    # Email destino
    while [ -z "$EMAIL_DESTINO" ]; do
        echo -e "${YELLOW}4. Email destino (donde recibir transcripciones):${NC}"
        read -p "Ingresa email destino: " EMAIL_DESTINO
        
        if [[ ! $EMAIL_DESTINO =~ @ ]]; then
            error "Debe ser un email válido"
            EMAIL_DESTINO=""
        fi
    done
    
    # PocketBase URL
    while [ -z "$POCKETBASE_URL" ]; do
        echo -e "${YELLOW}5. URL de PocketBase:${NC}"
        echo "   • Ejemplo: http://localhost:8090 o https://tu-pocketbase.com"
        read -p "Ingresa la URL de PocketBase: " POCKETBASE_URL
        
        # Remover trailing slash
        POCKETBASE_URL=$(echo $POCKETBASE_URL | sed 's/\/$//')
        
        if [[ ! $POCKETBASE_URL =~ ^https?:// ]]; then
            error "La URL debe empezar con http:// o https://"
            POCKETBASE_URL=""
        fi
    done
    
    # PocketBase Email Admin
    while [ -z "$POCKETBASE_EMAIL" ]; do
        echo -e "${YELLOW}6. Email Admin de PocketBase:${NC}"
        read -p "Ingresa el email admin de PocketBase: " POCKETBASE_EMAIL
        
        if [[ ! $POCKETBASE_EMAIL =~ @ ]]; then
            error "Debe ser un email válido"
            POCKETBASE_EMAIL=""
        fi
    done
    
    # PocketBase Password
    while [ -z "$POCKETBASE_PASSWORD" ]; do
        echo -e "${YELLOW}7. Contraseña Admin de PocketBase:${NC}"
        read -s -p "Ingresa la contraseña admin de PocketBase: " POCKETBASE_PASSWORD
        echo
        
        if [ ${#POCKETBASE_PASSWORD} -lt 8 ]; then
            error "La contraseña debe tener al menos 8 caracteres"
            POCKETBASE_PASSWORD=""
        fi
    done
    
    log "Credenciales configuradas correctamente"
}

crear_directorio_instalacion() {
    header "📁 CREANDO DIRECTORIO DE INSTALACIÓN"
    
    # Limpiar instalación anterior si existe
    if [ -d "$INSTALL_DIR" ]; then
        warning "Directorio existente encontrado, creando backup..."
        mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Crear directorio
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    log "Directorio creado: $INSTALL_DIR"
}

crear_transcriptor() {
    header "🤖 CREANDO TRANSCRIPTOR AUTOMÁTICO CON POCKETBASE"
    
    cat << 'PYTHON_EOF' > transcriptor_automatico.py
#!/usr/bin/env python3
"""
Transcriptor Automático FreePBX con OpenAI y PocketBase
Monitorea nuevas grabaciones, transcribe y almacena en PocketBase
"""

import os
import sys
import time
import threading
import json
from pathlib import Path
from datetime import datetime
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import re
import requests

# Función para email aislada (evita conflictos con Asterisk)
def enviar_email_seguro(asunto, mensaje, destinatario, usuario, password):
    """Envía email evitando conflictos con Asterisk"""
    try:
        import smtplib
        import ssl
        
        context = ssl.create_default_context()
        
        email_content = f"""To: {destinatario}
Subject: {asunto}
Content-Type: text/html; charset=utf-8

{mensaje}
"""
        
        with smtplib.SMTP("smtp.gmail.com", 587) as server:
            server.starttls(context=context)
            server.login(usuario, password)
            server.sendmail(usuario, destinatario, email_content.encode('utf-8'))
        
        return True
        
    except Exception as e:
        print(f"❌ Error email: {e}")
        return False

# Importar OpenAI primero
try:
    from openai import OpenAI
    print("✅ OpenAI importado correctamente")
except ImportError as e:
    print(f"❌ Error OpenAI: {e}")
    sys.exit(1)

# =============================================================================
# CONFIGURACIÓN (SERÁ REEMPLAZADA POR EL INSTALADOR)
# =============================================================================

# OpenAI API
OPENAI_API_KEY = "PLACEHOLDER_OPENAI_KEY"

# FreePBX
CARPETA_GRABACIONES = "/var/spool/asterisk/monitor"

# EMAIL GMAIL
EMAIL_USUARIO = "PLACEHOLDER_EMAIL_USUARIO"
EMAIL_PASSWORD = "PLACEHOLDER_EMAIL_PASSWORD"
EMAIL_DESTINO = "PLACEHOLDER_EMAIL_DESTINO"

# POCKETBASE
POCKETBASE_URL = "PLACEHOLDER_POCKETBASE_URL"
POCKETBASE_EMAIL = "PLACEHOLDER_POCKETBASE_EMAIL"
POCKETBASE_PASSWORD = "PLACEHOLDER_POCKETBASE_PASSWORD"

# Configuración Whisper
WHISPER_MODEL = "whisper-1"
WHISPER_LANGUAGE = "es"

# Configuración del monitor
DELAY_PROCESAMIENTO = 30  # Esperar 30 segundos después de detectar archivo
EXTENSIONES_AUDIO = ['.wav', '.mp3', '.m4a', '.flac']

# =============================================================================
# CLASE POCKETBASE
# =============================================================================

class PocketBaseManager:
    """Gestiona la integración con PocketBase"""
    
    def __init__(self, url, admin_email, admin_password):
        self.url = url.rstrip('/')
        self.admin_email = admin_email
        self.admin_password = admin_password
        self.token = None
        self.session = requests.Session()
        
    def authenticate(self):
        """Autentica con PocketBase como admin"""
        try:
            auth_url = f"{self.url}/api/admins/auth-with-password"
            data = {
                "identity": self.admin_email,
                "password": self.admin_password
            }
            
            response = self.session.post(auth_url, json=data)
            response.raise_for_status()
            
            auth_data = response.json()
            self.token = auth_data.get('token')
            
            # Configurar headers para futuras requests
            self.session.headers.update({
                'Authorization': f'Bearer {self.token}',
                'Content-Type': 'application/json'
            })
            
            print("✅ PocketBase: Autenticación exitosa")
            return True
            
        except Exception as e:
            print(f"❌ Error autenticando con PocketBase: {e}")
            return False
    
    def create_collection_if_not_exists(self):
        """Crea la colección 'transcripciones' si no existe"""
        try:
            # Verificar si la colección existe
            collections_url = f"{self.url}/api/collections"
            response = self.session.get(collections_url)
            response.raise_for_status()
            
            collections = response.json()
            collection_names = [col['name'] for col in collections.get('items', [])]
            
            if 'transcripciones' in collection_names:
                print("✅ PocketBase: Colección 'transcripciones' ya existe")
                return True
            
            # Crear la colección
            collection_schema = {
                "name": "transcripciones",
                "type": "base",
                "schema": [
                    {
                        "name": "archivo_nombre",
                        "type": "text",
                        "required": True,
                        "options": {
                            "min": 1,
                            "max": 255
                        }
                    },
                    {
                        "name": "tipo_llamada",
                        "type": "text",
                        "required": True,
                        "options": {
                            "min": 1,
                            "max": 50
                        }
                    },
                    {
                        "name": "extension",
                        "type": "text",
                        "required": False,
                        "options": {
                            "max": 20
                        }
                    },
                    {
                        "name": "numero_caller",
                        "type": "text",
                        "required": False,
                        "options": {
                            "max": 50
                        }
                    },
                    {
                        "name": "fecha_llamada",
                        "type": "date",
                        "required": False
                    },
                    {
                        "name": "duracion_segundos",
                        "type": "number",
                        "required": False
                    },
                    {
                        "name": "tamaño_mb",
                        "type": "number",
                        "required": False
                    },
                    {
                        "name": "transcripcion",
                        "type": "editor",
                        "required": True,
                        "options": {
                            "convertUrls": False
                        }
                    },
                    {
                        "name": "modelo_ia",
                        "type": "text",
                        "required": False,
                        "options": {
                            "max": 50
                        }
                    },
                    {
                        "name": "procesado_fecha",
                        "type": "date",
                        "required": True
                    },
                    {
                        "name": "email_enviado",
                        "type": "bool",
                        "required": True
                    },
                    {
                        "name": "ruta_archivo",
                        "type": "text",
                        "required": False,
                        "options": {
                            "max": 500
                        }
                    }
                ],
                "listRule": "",
                "viewRule": "",
                "createRule": "",
                "updateRule": "",
                "deleteRule": ""
            }
            
            response = self.session.post(collections_url, json=collection_schema)
            response.raise_for_status()
            
            print("✅ PocketBase: Colección 'transcripciones' creada exitosamente")
            return True
            
        except Exception as e:
            print(f"❌ Error creando colección en PocketBase: {e}")
            return False
    
    def save_transcription(self, transcription_data):
        """Guarda una transcripción en PocketBase"""
        try:
            save_url = f"{self.url}/api/collections/transcripciones/records"
            
            response = self.session.post(save_url, json=transcription_data)
            response.raise_for_status()
            
            record = response.json()
            print(f"✅ PocketBase: Transcripción guardada con ID: {record.get('id')}")
            return record
            
        except Exception as e:
            print(f"❌ Error guardando en PocketBase: {e}")
            return None
    
    def test_connection(self):
        """Prueba la conexión con PocketBase"""
        try:
            health_url = f"{self.url}/api/health"
            response = self.session.get(health_url, timeout=10)
            response.raise_for_status()
            
            print("✅ PocketBase: Conexión exitosa")
            return True
            
        except Exception as e:
            print(f"❌ Error conectando con PocketBase: {e}")
            return False

# =============================================================================
# CLASES PRINCIPALES
# =============================================================================

class AnalizadorMetadatos:
    """Extrae información del nombre del archivo FreePBX"""
    
    @staticmethod
    def extraer_info(nombre_archivo):
        """
        Extrae metadatos del nombre del archivo FreePBX
        Formato: external-2002-8493895277-20250523-090937-1748005759.433.wav
        """
        info = {
            'archivo': nombre_archivo,
            'tipo_llamada': 'desconocido',
            'extension': None,
            'numero_caller': None,
            'fecha': None,
            'hora': None,
            'timestamp': None,
            'tipo_icono': '📞',
            'descripcion': 'Llamada desconocida',
            'fecha_completa': None
        }
        
        # Remover extensión del archivo
        nombre_sin_ext = Path(nombre_archivo).stem
        
        # Patrón principal: tipo-extension-numero-fecha-hora-timestamp
        patron_principal = r'^(external|internal|in|out)-(\d+)-([^-]+)-(\d{8})-(\d{6})-(.+)$'
        match = re.match(patron_principal, nombre_sin_ext)
        
        if match:
            tipo, extension, numero, fecha_str, hora_str, timestamp = match.groups()
            
            # Tipo de llamada
            if tipo == 'external':
                info['tipo_llamada'] = 'entrante_externa'
                info['tipo_icono'] = '📥'
                info['descripcion'] = f'Llamada entrante externa'
            elif tipo == 'internal':
                info['tipo_llamada'] = 'interna'
                info['tipo_icono'] = '🏢'
                info['descripcion'] = f'Llamada interna'
            elif tipo == 'in':
                info['tipo_llamada'] = 'entrante'
                info['tipo_icono'] = '📥'
                info['descripcion'] = f'Llamada entrante'
            elif tipo == 'out':
                info['tipo_llamada'] = 'saliente'
                info['tipo_icono'] = '📤'
                info['descripcion'] = f'Llamada saliente'
            
            # Datos extraídos
            info['extension'] = extension
            info['numero_caller'] = numero
            info['timestamp'] = timestamp
            
            # Procesar fecha y hora
            try:
                fecha_dt = datetime.strptime(fecha_str + hora_str, '%Y%m%d%H%M%S')
                info['fecha'] = fecha_dt.strftime('%d/%m/%Y')
                info['hora'] = fecha_dt.strftime('%H:%M:%S')
                info['fecha_completa'] = fecha_dt
            except:
                info['fecha'] = fecha_str
                info['hora'] = hora_str
        
        else:
            # Patrones alternativos más simples
            patron_simple = r'^(in|out)-(\d+)-([^-]+)-(\d+)$'
            match_simple = re.match(patron_simple, nombre_sin_ext)
            
            if match_simple:
                direccion, extension, numero, timestamp = match_simple.groups()
                info['tipo_llamada'] = 'entrante' if direccion == 'in' else 'saliente'
                info['tipo_icono'] = '📥' if direccion == 'in' else '📤'
                info['extension'] = extension
                info['numero_caller'] = numero
                info['timestamp'] = timestamp
        
        return info

class TranscriptorAutomatico:
    """Transcriptor principal con monitoreo automático y PocketBase"""
    
    def __init__(self):
        print("🤖 TRANSCRIPTOR AUTOMÁTICO FREEPBX + POCKETBASE")
        print("=" * 50)
        
        if not self.verificar_configuracion():
            sys.exit(1)
        
        self.client = OpenAI(api_key=OPENAI_API_KEY)
        self.archivos_procesados = set()
        self.analizador = AnalizadorMetadatos()
        
        # Inicializar PocketBase
        self.pocketbase = PocketBaseManager(POCKETBASE_URL, POCKETBASE_EMAIL, POCKETBASE_PASSWORD)
        if not self.inicializar_pocketbase():
            sys.exit(1)
        
        print("✅ Sistema inicializado correctamente")
    
    def verificar_configuracion(self):
        """Verifica configuración"""
        errores = []
        
        if not Path(CARPETA_GRABACIONES).exists():
            errores.append(f"❌ No existe: {CARPETA_GRABACIONES}")
        
        if OPENAI_API_KEY == "PLACEHOLDER_OPENAI_KEY":
            errores.append("❌ Configura OPENAI_API_KEY")
        
        if EMAIL_USUARIO == "PLACEHOLDER_EMAIL_USUARIO":
            errores.append("❌ Configura EMAIL_USUARIO")
        
        if EMAIL_PASSWORD == "PLACEHOLDER_EMAIL_PASSWORD":
            errores.append("❌ Configura EMAIL_PASSWORD")
        
        if EMAIL_DESTINO == "PLACEHOLDER_EMAIL_DESTINO":
            errores.append("❌ Configura EMAIL_DESTINO")
        
        if POCKETBASE_URL == "PLACEHOLDER_POCKETBASE_URL":
            errores.append("❌ Configura POCKETBASE_URL")
        
        if POCKETBASE_EMAIL == "PLACEHOLDER_POCKETBASE_EMAIL":
            errores.append("❌ Configura POCKETBASE_EMAIL")
        
        if POCKETBASE_PASSWORD == "PLACEHOLDER_POCKETBASE_PASSWORD":
            errores.append("❌ Configura POCKETBASE_PASSWORD")
        
        if errores:
            print("🔧 ERRORES DE CONFIGURACIÓN:")
            for error in errores:
                print(f"  {error}")
            return False
        
        print("✅ Configuración válida")
        return True
    
    def inicializar_pocketbase(self):
        """Inicializa y configura PocketBase"""
        print("\n🗄️ INICIALIZANDO POCKETBASE")
        
        # Probar conexión
        if not self.pocketbase.test_connection():
            return False
        
        # Autenticar
        if not self.pocketbase.authenticate():
            return False
        
        # Crear colección si no existe
        if not self.pocketbase.create_collection_if_not_exists():
            return False
        
        print("✅ PocketBase inicializado correctamente")
        return True
    
    def transcribir_archivo(self, archivo_path):
        """Transcribe archivo con OpenAI"""
        print(f"🎙️ Transcribiendo: {archivo_path.name}")
        
        # Verificar tamaño
        tamaño_mb = archivo_path.stat().st_size / (1024 * 1024)
        if tamaño_mb > 24:
            print(f"❌ Archivo muy grande: {tamaño_mb:.1f}MB (máximo 25MB)")
            return None
        
        try:
            with open(archivo_path, "rb") as audio_file:
                response = self.client.audio.transcriptions.create(
                    file=audio_file,
                    model=WHISPER_MODEL,
                    language=WHISPER_LANGUAGE,
                    response_format="text"
                )
            
            transcripcion = response.strip()
            
            if not transcripcion:
                print("⚠️ No se detectó texto")
                return None
            
            print(f"✅ Transcripción completada: {len(transcripcion)} caracteres")
            return transcripcion
            
        except Exception as e:
            print(f"❌ Error transcribiendo: {e}")
            return None
    
    def crear_email_html(self, info, transcripcion, archivo_path):
        """Crea email HTML con la información completa"""
        tamaño_mb = archivo_path.stat().st_size / (1024 * 1024)
        duracion_est = int(tamaño_mb * 8)  # Estimación aproximada en segundos
        
        html = f"""
        <!DOCTYPE html>
        <html>
        <head><meta charset="UTF-8"></head>
        <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 800px; margin: 0 auto;">
            
            <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 10px; text-align: center; margin-bottom: 20px;">
                <h1 style="margin: 0; font-size: 24px;">🎙️ Nueva Transcripción FreePBX</h1>
                <p style="margin: 10px 0 0 0; opacity: 0.9;">Sistema automático con PocketBase</p>
            </div>
            
            <div style="background: #f8f9fa; padding: 20px; border-radius: 10px; margin: 20px 0; border-left: 5px solid #007bff;">
                <h2 style="margin-top: 0; color: #007bff;">{info['tipo_icono']} Información de la Llamada</h2>
                <table style="width: 100%; border-collapse: collapse;">
                    <tr style="border-bottom: 1px solid #dee2e6;">
                        <td style="padding: 8px; font-weight: bold; width: 150px;">Archivo:</td>
                        <td style="padding: 8px;">{info['archivo']}</td>
                    </tr>
                    <tr style="border-bottom: 1px solid #dee2e6;">
                        <td style="padding: 8px; font-weight: bold;">Tipo:</td>
                        <td style="padding: 8px;">{info['tipo_icono']} {info['descripcion']}</td>
                    </tr>
                    <tr style="border-bottom: 1px solid #dee2e6;">
                        <td style="padding: 8px; font-weight: bold;">Extensión:</td>
                        <td style="padding: 8px; color: #007bff; font-weight: bold;">{info['extension'] or 'N/A'}</td>
                    </tr>
                    <tr style="border-bottom: 1px solid #dee2e6;">
                        <td style="padding: 8px; font-weight: bold;">Número Caller:</td>
                        <td style="padding: 8px; color: #28a745; font-weight: bold;">{info['numero_caller'] or 'N/A'}</td>
                    </tr>
                    <tr style="border-bottom: 1px solid #dee2e6;">
                        <td style="padding: 8px; font-weight: bold;">Fecha:</td>
                        <td style="padding: 8px;">{info['fecha'] or 'N/A'}</td>
                    </tr>
                    <tr style="border-bottom: 1px solid #dee2e6;">
                        <td style="padding: 8px; font-weight: bold;">Hora:</td>
                        <td style="padding: 8px;">{info['hora'] or 'N/A'}</td>
                    </tr>
                    <tr style="border-bottom: 1px solid #dee2e6;">
                        <td style="padding: 8px; font-weight: bold;">Tamaño:</td>
                        <td style="padding: 8px;">{tamaño_mb:.2f} MB</td>
                    </tr>
                    <tr style="border-bottom: 1px solid #dee2e6;">
                        <td style="padding: 8px; font-weight: bold;">Duración est.:</td>
                        <td style="padding: 8px;">~{duracion_est} segundos</td>
                    </tr>
                    <tr>
                        <td style="padding: 8px; font-weight: bold;">Procesado:</td>
                        <td style="padding: 8px;">{datetime.now().strftime('%d/%m/%Y %H:%M:%S')}</td>
                    </tr>
                </table>
            </div>
            
            <div style="background: #fff3cd; padding: 20px; border-radius: 10px; margin: 20px 0; border-left: 5px solid #ffc107;">
                <h2 style="margin-top: 0; color: #856404;">📝 Transcripción Completa</h2>
                <div style="background: white; padding: 20px; border-radius: 8px; border: 1px solid #ffeaa7; font-family: 'Segoe UI', Arial, sans-serif; line-height: 1.8; color: #2d3436;">
{transcripcion}
                </div>
            </div>
            
            <div style="background: #d4edda; padding: 15px; border-radius: 8px; margin: 20px 0; border-left: 5px solid #28a745;">
                <p style="margin: 0; color: #155724;"><strong>🗄️ Almacenado en PocketBase</strong></p>
                <p style="margin: 5px 0 0 0; color: #155724; font-size: 14px;">Esta transcripción ha sido guardada automáticamente en la base de datos</p>
            </div>
            
            <div style="background: #e8f4fd; padding: 15px; border-radius: 8px; text-align: center; font-size: 12px; color: #666; margin-top: 30px;">
                <p style="margin: 0;"><strong>🤖 Transcripción Automática FreePBX + PocketBase</strong></p>
                <p style="margin: 5px 0 0 0;">OpenAI Whisper API • Generado el {datetime.now().strftime('%d/%m/%Y a las %H:%M:%S')}</p>
            </div>
            
        </body>
        </html>
        """
        return html
    
    def guardar_transcripcion_local(self, archivo_path, transcripcion, info):
        """Guarda transcripción localmente"""
        archivo_txt = archivo_path.with_suffix('.txt')
        
        try:
            with open(archivo_txt, 'w', encoding='utf-8') as f:
                f.write("=" * 60 + "\n")
                f.write("TRANSCRIPCIÓN AUTOMÁTICA FREEPBX + POCKETBASE\n")
                f.write("=" * 60 + "\n\n")
                
                f.write(f"INFORMACIÓN DE LA LLAMADA:\n")
                f.write(f"- Archivo: {info['archivo']}\n")
                f.write(f"- Tipo: {info['descripcion']}\n")
                f.write(f"- Extensión: {info['extension']}\n")
                f.write(f"- Número Caller: {info['numero_caller']}\n")
                f.write(f"- Fecha: {info['fecha']}\n")
                f.write(f"- Hora: {info['hora']}\n")
                f.write(f"- Timestamp: {info['timestamp']}\n")
                f.write(f"- Procesado: {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}\n")
                f.write(f"- Modelo: OpenAI {WHISPER_MODEL}\n")
                
                f.write("\n" + "=" * 60 + "\n")
                f.write("TRANSCRIPCIÓN:\n")
                f.write("=" * 60 + "\n\n")
                f.write(transcripcion)
            
            print(f"💾 Transcripción guardada localmente: {archivo_txt.name}")
            return archivo_txt
            
        except Exception as e:
            print(f"❌ Error guardando transcripción local: {e}")
            return None
    
    def guardar_en_pocketbase(self, info, transcripcion, archivo_path):
        """Guarda la transcripción en PocketBase"""
        try:
            tamaño_mb = archivo_path.stat().st_size / (1024 * 1024)
            duracion_est = int(tamaño_mb * 8)
            
            # Preparar datos para PocketBase
            transcription_data = {
                "archivo_nombre": info['archivo'],
                "tipo_llamada": info['tipo_llamada'],
                "extension": info['extension'],
                "numero_caller": info['numero_caller'],
                "fecha_llamada": info['fecha_completa'].isoformat() if info['fecha_completa'] else None,
                "duracion_segundos": duracion_est,
                "tamaño_mb": round(tamaño_mb, 2),
                "transcripcion": transcripcion,
                "modelo_ia": f"OpenAI {WHISPER_MODEL}",
                "procesado_fecha": datetime.now().isoformat(),
                "email_enviado": False,  # Se actualizará después del envío
                "ruta_archivo": str(archivo_path)
            }
            
            # Guardar en PocketBase
            record = self.pocketbase.save_transcription(transcription_data)
            
            if record:
                print(f"🗄️ Guardado en PocketBase con ID: {record.get('id')}")
                return record
            else:
                print("❌ Error guardando en PocketBase")
                return None
                
        except Exception as e:
            print(f"❌ Error preparando datos para PocketBase: {e}")
            return None
    
    def actualizar_email_enviado(self, record_id, email_ok):
        """Actualiza el estado del email en PocketBase"""
        try:
            if not record_id:
                return
                
            update_url = f"{self.pocketbase.url}/api/collections/transcripciones/records/{record_id}"
            update_data = {"email_enviado": email_ok}
            
            response = self.pocketbase.session.patch(update_url, json=update_data)
            response.raise_for_status()
            
            print(f"🗄️ Estado del email actualizado en PocketBase")
            
        except Exception as e:
            print(f"❌ Error actualizando estado del email: {e}")
    
    def procesar_archivo(self, archivo_path):
        """Procesa un archivo de audio completo"""
        if str(archivo_path) in self.archivos_procesados:
            return
        
        print(f"\n{'='*60}")
        print(f"🔄 PROCESANDO NUEVO ARCHIVO")
        print(f"{'='*60}")
        
        # Extraer metadatos
        info = self.analizador.extraer_info(archivo_path.name)
        
        print(f"📁 Archivo: {info['archivo']}")
        print(f"{info['tipo_icono']} Tipo: {info['descripcion']}")
        print(f"📱 Extensión: {info['extension']}")
        print(f"📞 Caller: {info['numero_caller']}")
        print(f"📅 Fecha: {info['fecha']} {info['hora']}")
        
        # Transcribir
        transcripcion = self.transcribir_archivo(archivo_path)
        if not transcripcion:
            self.archivos_procesados.add(str(archivo_path))
            return
        
        # Guardar localmente
        archivo_txt = self.guardar_transcripcion_local(archivo_path, transcripcion, info)
        
        # Guardar en PocketBase
        pocketbase_record = self.guardar_en_pocketbase(info, transcripcion, archivo_path)
        
        # Crear email
        fecha_hora = f"{info['fecha']} {info['hora']}" if info['fecha'] and info['hora'] else "Fecha desconocida"
        asunto = f"{info['tipo_icono']} {info['descripcion']} - Ext {info['extension']} - {fecha_hora}"
        
        mensaje_html = self.crear_email_html(info, transcripcion, archivo_path)
        
        # Enviar email
        print("\n📧 Enviando email...")
        email_ok = enviar_email_seguro(asunto, mensaje_html, EMAIL_DESTINO, EMAIL_USUARIO, EMAIL_PASSWORD)
        
        # Actualizar estado del email en PocketBase
        if pocketbase_record:
            self.actualizar_email_enviado(pocketbase_record.get('id'), email_ok)
        
        # Marcar como procesado
        self.archivos_procesados.add(str(archivo_path))
        
        print(f"\n{'='*60}")
        print(f"✅ ARCHIVO PROCESADO COMPLETAMENTE")
        print(f"{'='*60}")
        print(f"📄 Archivo TXT: {archivo_txt.name if archivo_txt else 'Error'}")
        print(f"🗄️ PocketBase: {'✅ Guardado' if pocketbase_record else '❌ Error'}")
        print(f"📧 Email enviado: {'✅ Sí' if email_ok else '❌ No'}")
        print(f"📝 Caracteres transcritos: {len(transcripcion)}")
        
        # Preview de la transcripción
        if len(transcripcion) > 0:
            print(f"\n📋 PREVIEW:")
            print("-" * 40)
            preview = transcripcion[:200] + "..." if len(transcripcion) > 200 else transcripcion
            print(preview)
            print("-" * 40)

class MonitorArchivos(FileSystemEventHandler):
    """Monitor de archivos para detectar nuevas grabaciones"""
    
    def __init__(self, transcriptor):
        self.transcriptor = transcriptor
        self.archivos_pendientes = {}
        self.timer = None
        print("👁️ Monitor de archivos inicializado")
    
    def on_created(self, event):
        if not event.is_directory:
            self.archivo_detectado(event.src_path)
    
    def on_modified(self, event):
        if not event.is_directory:
            self.archivo_detectado(event.src_path)
    
    def archivo_detectado(self, ruta_archivo):
        """Se ejecuta cuando se detecta un archivo nuevo o modificado"""
        archivo = Path(ruta_archivo)
        
        # Solo procesar archivos de audio
        if archivo.suffix.lower() in EXTENSIONES_AUDIO:
            print(f"\n👁️ ARCHIVO DETECTADO: {archivo.name}")
            print(f"📂 Ruta: {archivo.parent}")
            print(f"⏰ Hora: {datetime.now().strftime('%H:%M:%S')}")
            
            # Agregar a lista de pendientes
            self.archivos_pendientes[str(archivo)] = time.time()
            self.programar_procesamiento()
    
    def programar_procesamiento(self):
        """Programa procesamiento con delay para que termine de escribirse el archivo"""
        if self.timer:
            self.timer.cancel()
        
        print(f"⏳ Esperando {DELAY_PROCESAMIENTO} segundos para procesar...")
        self.timer = threading.Timer(DELAY_PROCESAMIENTO, self.procesar_archivos_pendientes)
        self.timer.start()
    
    def procesar_archivos_pendientes(self):
        """Procesa los archivos que están pendientes"""
        ahora = time.time()
        
        for archivo_str, timestamp in list(self.archivos_pendientes.items()):
            archivo = Path(archivo_str)
            
            if not archivo.exists():
                del self.archivos_pendientes[archivo_str]
                continue
            
            # Si ha pasado suficiente tiempo y el archivo está estable
            if ahora - timestamp >= DELAY_PROCESAMIENTO and self.archivo_estable(archivo):
                print(f"\n🚀 Iniciando procesamiento de: {archivo.name}")
                self.transcriptor.procesar_archivo(archivo)
                del self.archivos_pendientes[archivo_str]
        
        # Si quedan archivos pendientes, reprogramar
        if self.archivos_pendientes:
            self.programar_procesamiento()
    
    def archivo_estable(self, archivo):
        """Verifica que el archivo no se esté escribiendo actualmente"""
        try:
            tamaño1 = archivo.stat().st_size
            time.sleep(2)
            tamaño2 = archivo.stat().st_size
            return tamaño1 == tamaño2 and tamaño1 > 1000  # Mínimo 1KB
        except:
            return False

def main():
    """Función principal - Inicia el monitoreo automático"""
    
    print("🤖 INICIANDO TRANSCRIPTOR AUTOMÁTICO FREEPBX + POCKETBASE")
    print("=" * 60)
    
    # Crear transcriptor
    transcriptor = TranscriptorAutomatico()
    
    # Crear monitor de archivos
    event_handler = MonitorArchivos(transcriptor)
    observer = Observer()
    observer.schedule(event_handler, CARPETA_GRABACIONES, recursive=True)
    
    # Iniciar monitoreo
    observer.start()
    
    print(f"\n🎯 SISTEMA ACTIVO - MONITOREO AUTOMÁTICO")
    print(f"📁 Carpeta monitoreada: {CARPETA_GRABACIONES}")
    print(f"📧 Emails se envían a: {EMAIL_DESTINO}")
    print(f"🗄️ Base de datos: {POCKETBASE_URL}")
    print(f"⏱️ Delay de procesamiento: {DELAY_PROCESAMIENTO} segundos")
    print(f"🎙️ Modelo: OpenAI {WHISPER_MODEL}")
    print(f"🔄 Presiona Ctrl+C para detener...\n")
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n⏹️ Deteniendo sistema...")
        observer.stop()
    
    observer.join()
    print("👋 Sistema detenido correctamente")

if __name__ == "__main__":
    main()
PYTHON_EOF
    
    # Hacer ejecutable
    chmod +x transcriptor_automatico.py
    log "Transcriptor con PocketBase creado correctamente"
}

aplicar_configuracion() {
    header "⚙️ APLICANDO CONFIGURACIÓN"
    
    # Escapar caracteres especiales en las credenciales para sed
    OPENAI_API_KEY_ESCAPED=$(printf '%s\n' "$OPENAI_API_KEY" | sed 's/[[\.*^$()+?{|]/\\&/g')
    EMAIL_USUARIO_ESCAPED=$(printf '%s\n' "$EMAIL_USUARIO" | sed 's/[[\.*^$()+?{|]/\\&/g')
    EMAIL_PASSWORD_ESCAPED=$(printf '%s\n' "$EMAIL_PASSWORD" | sed 's/[[\.*^$()+?{|]/\\&/g')
    EMAIL_DESTINO_ESCAPED=$(printf '%s\n' "$EMAIL_DESTINO" | sed 's/[[\.*^$()+?{|]/\\&/g')
    POCKETBASE_URL_ESCAPED=$(printf '%s\n' "$POCKETBASE_URL" | sed 's/[[\.*^$()+?{|]/\\&/g')
    POCKETBASE_EMAIL_ESCAPED=$(printf '%s\n' "$POCKETBASE_EMAIL" | sed 's/[[\.*^$()+?{|]/\\&/g')
    POCKETBASE_PASSWORD_ESCAPED=$(printf '%s\n' "$POCKETBASE_PASSWORD" | sed 's/[[\.*^$()+?{|]/\\&/g')
    
    # Reemplazar placeholders en el archivo
    sed -i "s/PLACEHOLDER_OPENAI_KEY/$OPENAI_API_KEY_ESCAPED/g" transcriptor_automatico.py
    sed -i "s/PLACEHOLDER_EMAIL_USUARIO/$EMAIL_USUARIO_ESCAPED/g" transcriptor_automatico.py
    sed -i "s/PLACEHOLDER_EMAIL_PASSWORD/$EMAIL_PASSWORD_ESCAPED/g" transcriptor_automatico.py
    sed -i "s/PLACEHOLDER_EMAIL_DESTINO/$EMAIL_DESTINO_ESCAPED/g" transcriptor_automatico.py
    sed -i "s|PLACEHOLDER_POCKETBASE_URL|$POCKETBASE_URL_ESCAPED|g" transcriptor_automatico.py
    sed -i "s/PLACEHOLDER_POCKETBASE_EMAIL/$POCKETBASE_EMAIL_ESCAPED/g" transcriptor_automatico.py
    sed -i "s/PLACEHOLDER_POCKETBASE_PASSWORD/$POCKETBASE_PASSWORD_ESCAPED/g" transcriptor_automatico.py
    
    log "Configuración aplicada al transcriptor"
    
    # Verificación adicional: Confirmar que los placeholders fueron reemplazados
    if grep -q "PLACEHOLDER_" transcriptor_automatico.py; then
        warning "Algunos placeholders no fueron reemplazados, aplicando método alternativo..."
        
        # Método alternativo usando Python para reemplazar
        python3 << PYFIX
import re

# Leer archivo
with open('transcriptor_automatico.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Reemplazar con método más robusto
content = content.replace('PLACEHOLDER_OPENAI_KEY', '$OPENAI_API_KEY')
content = content.replace('PLACEHOLDER_EMAIL_USUARIO', '$EMAIL_USUARIO')
content = content.replace('PLACEHOLDER_EMAIL_PASSWORD', '$EMAIL_PASSWORD')
content = content.replace('PLACEHOLDER_EMAIL_DESTINO', '$EMAIL_DESTINO')
content = content.replace('PLACEHOLDER_POCKETBASE_URL', '$POCKETBASE_URL')
content = content.replace('PLACEHOLDER_POCKETBASE_EMAIL', '$POCKETBASE_EMAIL')
content = content.replace('PLACEHOLDER_POCKETBASE_PASSWORD', '$POCKETBASE_PASSWORD')

# Escribir archivo
with open('transcriptor_automatico.py', 'w', encoding='utf-8') as f:
    f.write(content)

print("✅ Configuración aplicada con método alternativo")
PYFIX
        
        log "Configuración aplicada con método alternativo"
    fi
}

probar_configuracion() {
    header "🧪 PROBANDO CONFIGURACIÓN"
    
    info "Probando conexión con OpenAI, Gmail y PocketBase..."
    
    # Crear script de prueba temporal más robusto
    cat << TESTPY > test_config.py
#!/usr/bin/env python3
import sys
import requests

print("🔍 Probando configuraciones...")

# Probar OpenAI
try:
    from openai import OpenAI
    client = OpenAI(api_key="$OPENAI_API_KEY")
    models = client.models.list()
    print("✅ OpenAI: Conexión exitosa")
except Exception as e:
    print(f"❌ OpenAI Error: {e}")
    sys.exit(1)

# Probar Gmail
try:
    import smtplib
    import ssl
    
    context = ssl.create_default_context()
    with smtplib.SMTP("smtp.gmail.com", 587) as server:
        server.starttls(context=context)
        server.login("$EMAIL_USUARIO", "$EMAIL_PASSWORD")
    print("✅ Gmail: Autenticación exitosa")
except Exception as e:
    print(f"❌ Gmail Error: {e}")
    print("💡 Verifica tu App Password de Gmail")
    sys.exit(1)

# Probar PocketBase
try:
    pocketbase_url = "$POCKETBASE_URL".rstrip('/')
    
    # Probar conectividad
    health_response = requests.get(f"{pocketbase_url}/api/health", timeout=10)
    health_response.raise_for_status()
    print("✅ PocketBase: Conectividad exitosa")
    
    # Probar autenticación admin
    auth_url = f"{pocketbase_url}/api/admins/auth-with-password"
    auth_data = {
        "identity": "$POCKETBASE_EMAIL",
        "password": "$POCKETBASE_PASSWORD"
    }
    
    auth_response = requests.post(auth_url, json=auth_data, timeout=10)
    auth_response.raise_for_status()
    print("✅ PocketBase: Autenticación admin exitosa")
    
except Exception as e:
    print(f"❌ PocketBase Error: {e}")
    print("💡 Verifica que PocketBase esté ejecutándose y las credenciales sean correctas")
    sys.exit(1)

# Probar script principal
try:
    exec(open('transcriptor_automatico.py').read().split('if __name__')[0])
    print("✅ Script principal: Sintaxis correcta")
except Exception as e:
    print(f"❌ Script Error: {e}")
    sys.exit(1)

print("🎉 ¡Todas las configuraciones funcionan correctamente!")
TESTPY
    
    # Ejecutar prueba
    if python3 test_config.py; then
        log "Configuración probada exitosamente"
        rm test_config.py
    else
        error "Falla en la configuración"
        rm test_config.py
        
        # Ofrecer diagnóstico
        echo -e "${YELLOW}🔍 Ejecutando diagnóstico...${NC}"
        echo "Credenciales configuradas:"
        echo "- OpenAI API Key: ${OPENAI_API_KEY:0:10}..."
        echo "- Email Usuario: $EMAIL_USUARIO"
        echo "- Email Destino: $EMAIL_DESTINO"
        echo "- Password Length: ${#EMAIL_PASSWORD} caracteres"
        echo "- PocketBase URL: $POCKETBASE_URL"
        echo "- PocketBase Email: $POCKETBASE_EMAIL"
        
        exit 1
    fi
}

crear_scripts_gestion() {
    header "🛠️ CREANDO SCRIPTS DE GESTIÓN"
    
    # Script principal de gestión
    cat << 'SCRIPT_EOF' > freepbx-transcriptor
#!/bin/bash

INSTALL_DIR="/opt/freepbx-transcriptor"
SCRIPT_PATH="$INSTALL_DIR/transcriptor_automatico.py"
PIDFILE="/var/run/freepbx-transcriptor.pid"
LOGFILE="/var/log/freepbx-transcriptor.log"

case "$1" in
    start)
        if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
            echo "❌ El transcriptor ya está ejecutándose (PID: $(cat $PIDFILE))"
            exit 1
        fi
        
        echo "🚀 Iniciando transcriptor automático con PocketBase..."
        cd "$INSTALL_DIR"
        nohup python3 "$SCRIPT_PATH" > "$LOGFILE" 2>&1 &
        echo $! > "$PIDFILE"
        echo "✅ Transcriptor iniciado (PID: $!)"
        echo "📄 Logs: $LOGFILE"
        ;;
    
    stop)
        if [ -f "$PIDFILE" ]; then
            PID=$(cat "$PIDFILE")
            if kill -0 "$PID" 2>/dev/null; then
                echo "⏹️ Deteniendo transcriptor (PID: $PID)..."
                kill "$PID"
                rm -f "$PIDFILE"
                echo "✅ Transcriptor detenido"
            else
                echo "❌ El transcriptor no está ejecutándose"
                rm -f "$PIDFILE"
            fi
        else
            echo "❌ No se encontró archivo PID"
        fi
        ;;
    
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    
    status)
        if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
            echo "✅ Transcriptor ejecutándose (PID: $(cat $PIDFILE))"
            echo "📄 Logs: tail -f $LOGFILE"
        else
            echo "❌ Transcriptor no está ejecutándose"
        fi
        ;;
    
    logs)
        if [ -f "$LOGFILE" ]; then
            echo "📄 Últimas 50 líneas del log:"
            echo "================================"
            tail -n 50 "$LOGFILE"
            echo "================================"
            echo "Para seguir logs en tiempo real: tail -f $LOGFILE"
        else
            echo "❌ No se encontró archivo de log"
        fi
        ;;
    
    test)
        echo "🧪 Probando configuración..."
        cd "$INSTALL_DIR"
        python3 -c "
from transcriptor_automatico import *
t = TranscriptorAutomatico()
print('✅ Configuración correcta')
"
        ;;
    
    config)
        echo "⚙️ Editando configuración..."
        nano "$SCRIPT_PATH"
        echo "💡 Reinicia el servicio después de cambios: freepbx-transcriptor restart"
        ;;
    
    pocketbase-test)
        echo "🗄️ Probando conexión con PocketBase..."
        cd "$INSTALL_DIR"
        python3 -c "
from transcriptor_automatico import PocketBaseManager, POCKETBASE_URL, POCKETBASE_EMAIL, POCKETBASE_PASSWORD
pb = PocketBaseManager(POCKETBASE_URL, POCKETBASE_EMAIL, POCKETBASE_PASSWORD)
if pb.test_connection() and pb.authenticate():
    print('✅ PocketBase: Conexión y autenticación exitosa')
    if pb.create_collection_if_not_exists():
        print('✅ PocketBase: Colección verificada/creada')
else:
    print('❌ Error conectando con PocketBase')
"
        ;;
    
    install-service)
        echo "🔧 Instalando como servicio systemd..."
        
        cat << SYSTEMD_EOF > /etc/systemd/system/freepbx-transcriptor.service
[Unit]
Description=FreePBX Transcriptor Automático con PocketBase
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $SCRIPT_PATH
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF
        
        systemctl daemon-reload
        systemctl enable freepbx-transcriptor
        echo "✅ Servicio instalado"
        echo "Para iniciar: systemctl start freepbx-transcriptor"
        echo "Para ver logs: journalctl -u freepbx-transcriptor -f"
        ;;
    
    *)
        echo "🎙️ TRANSCRIPTOR AUTOMÁTICO FREEPBX + POCKETBASE"
        echo "==============================================="
        echo "Uso: $0 {start|stop|restart|status|logs|test|config|pocketbase-test|install-service}"
        echo ""
        echo "Comandos:"
        echo "  start           - Iniciar el transcriptor"
        echo "  stop            - Detener el transcriptor"
        echo "  restart         - Reiniciar el transcriptor"
        echo "  status          - Ver estado del servicio"
        echo "  logs            - Ver logs del transcriptor"
        echo "  test            - Probar configuración completa"
        echo "  config          - Editar configuración"
        echo "  pocketbase-test - Probar solo conexión PocketBase"
        echo "  install-service - Instalar como servicio systemd"
        echo ""
        echo "Archivos:"
        echo "  Script: $SCRIPT_PATH"
        echo "  Logs: $LOGFILE"
        echo "  PID: $PIDFILE"
        echo ""
        echo "Estado actual:"
        $0 status
        ;;
esac
SCRIPT_EOF
    
    chmod +x freepbx-transcriptor
    
    # Crear enlace simbólico
    ln -sf "$INSTALL_DIR/freepbx-transcriptor" /usr/local/bin/freepbx-transcriptor
    
    log "Scripts de gestión creados"
}

crear_documentacion() {
    header "📚 CREANDO DOCUMENTACIÓN"
    
    cat << 'DOC_EOF' > README.md
# 🎙️ Transcriptor Automático FreePBX + PocketBase

Sistema automático de transcripción de llamadas para FreePBX usando OpenAI Whisper API con almacenamiento en PocketBase.

## 📋 Características

- ✅ **Monitoreo automático** de nuevas grabaciones
- ✅ **Extracción de metadatos** del nombre del archivo
- ✅ **Transcripción con OpenAI** Whisper API
- ✅ **Almacenamiento en PocketBase** - Base de datos automática
- ✅ **Envío automático** por email (HTML profesional)
- ✅ **Guardado local** de transcripciones (.txt)
- ✅ **Gestión completa** con scripts de control
- ✅ **Creación automática** de estructura de BD

## 🗄️ Integración PocketBase

### Estructura de la Base de Datos
El sistema crea automáticamente la colección `transcripciones` con los siguientes campos:

- `archivo_nombre` (text) - Nombre del archivo de audio
- `tipo_llamada` (text) - Tipo de llamada (entrante, saliente, interna)
- `extension` (text) - Extensión que participó en la llamada
- `numero_caller` (text) - Número telefónico del caller
- `fecha_llamada` (date) - Fecha y hora de la llamada
- `duracion_segundos` (number) - Duración estimada en segundos
- `tamaño_mb` (number) - Tamaño del archivo en MB
- `transcripcion` (editor) - Texto completo de la transcripción
- `modelo_ia` (text) - Modelo de IA utilizado
- `procesado_fecha` (date) - Fecha de procesamiento
- `email_enviado` (bool) - Estado del envío por email
- `ruta_archivo` (text) - Ruta completa del archivo

### Ventajas del Almacenamiento
- **Búsqueda avanzada** de transcripciones
- **Histórico completo** de llamadas procesadas
- **API REST** para integraciones
- **Dashboard web** incluido en PocketBase
- **Backup automático** de datos

## 🚀 Uso

### Comandos básicos:
```bash
# Iniciar el transcriptor
freepbx-transcriptor start

# Ver estado
freepbx-transcriptor status

# Ver logs en tiempo real
freepbx-transcriptor logs

# Probar solo PocketBase
freepbx-transcriptor pocketbase-test

# Detener
freepbx-transcriptor stop

# Reiniciar
freepbx-transcriptor restart
```

### Instalar como servicio del sistema:
```bash
freepbx-transcriptor install-service
systemctl start freepbx-transcriptor
systemctl status freepbx-transcriptor
```

## 📁 Archivos

- **Script principal**: `/opt/freepbx-transcriptor/transcriptor_automatico.py`
- **Logs**: `/var/log/freepbx-transcriptor.log`
- **Gestión**: `/usr/local/bin/freepbx-transcriptor`

## 🔧 Configuración

Para cambiar configuración:
```bash
freepbx-transcriptor config
```

### Configuraciones incluidas:
- **OpenAI API Key** - Para transcripción
- **Gmail SMTP** - Para envío de emails
- **PocketBase** - URL y credenciales admin

## 📞 Formatos de archivo soportados

El sistema extrae automáticamente información de nombres como:
- `external-2002-8493895277-20250523-090937-1748005759.433.wav`
- `in-1001-5551234567-20250523-143022.wav`
- `out-2002-5559876543-20250523-151530.wav`

## 📧 Email + Base de Datos

Los emails incluyen:
- Información completa de la llamada
- Metadatos extraídos automáticamente
- Transcripción completa formateada
- Diseño HTML profesional
- **Indicador de almacenamiento en PocketBase**

Simultáneamente, toda la información se guarda en PocketBase para:
- Consultas posteriores
- Análisis de llamadas
- Integraciones con otros sistemas

## 🗄️ Acceso a PocketBase

Una vez configurado, puedes acceder a:
- **Admin Panel**: `http://tu-pocketbase:8090/_/`
- **API REST**: `http://tu-pocketbase:8090/api/`
- **Colección**: `http://tu-pocketbase:8090/api/collections/transcripciones/records`

## 💰 Costos

OpenAI Whisper API: ~$0.006 por minuto de audio
- 1 hora de audio ≈ $0.36
- 100 llamadas de 5 minutos ≈ $3.00

PocketBase: Gratuito y open source

## 🆘 Soporte

Para problemas o dudas:
1. Verificar logs: `freepbx-transcriptor logs`
2. Probar configuración: `freepbx-transcriptor test`
3. Probar PocketBase: `freepbx-transcriptor pocketbase-test`
4. Revisar estado: `freepbx-transcriptor status`

## 🔧 Requisitos de PocketBase

- PocketBase ejecutándose y accesible
- Usuario admin configurado
- Conexión de red entre FreePBX y PocketBase

## 🔄 Flujo de Trabajo

1. **Detección** - Se detecta nueva grabación
2. **Transcripción** - OpenAI procesa el audio
3. **Almacenamiento** - Se guarda en PocketBase
4. **Email** - Se envía notificación por email
5. **Actualización** - Se marca el estado del email

---
Instalado el $(date) - VERSION CON POCKETBASE
DOC_EOF
    
    log "Documentación creada: README.md"
}

mostrar_resumen() {
    header "
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   ✅ INSTALACIÓN COMPLETADA EXITOSAMENTE                     ║
║        🗄️  CON INTEGRACIÓN POCKETBASE                       ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
"
    
    echo -e "${WHITE}📋 RESUMEN DE LA INSTALACIÓN:${NC}"
    echo -e "${GREEN}  ✅ Sistema verificado${NC}"
    echo -e "${GREEN}  ✅ Dependencias instaladas${NC}"
    echo -e "${GREEN}  ✅ Credenciales configuradas${NC}"
    echo -e "${GREEN}  ✅ Transcriptor con PocketBase creado${NC}"
    echo -e "${GREEN}  ✅ Configuración aplicada${NC}"
    echo -e "${GREEN}  ✅ Configuración probada (incluye PocketBase)${NC}"
    echo -e "${GREEN}  ✅ Scripts de gestión creados${NC}"
    echo -e "${GREEN}  ✅ Documentación generada${NC}"
    
    echo -e "\n${WHITE}📁 ARCHIVOS INSTALADOS:${NC}"
    echo -e "${BLUE}  📂 Directorio principal: ${INSTALL_DIR}${NC}"
    echo -e "${BLUE}  🤖 Script principal: ${INSTALL_DIR}/transcriptor_automatico.py${NC}"
    echo -e "${BLUE}  🛠️ Gestión: /usr/local/bin/freepbx-transcriptor${NC}"
    echo -e "${BLUE}  📄 Logs: /var/log/freepbx-transcriptor.log${NC}"
    echo -e "${BLUE}  📚 Documentación: ${INSTALL_DIR}/README.md${NC}"
    
    echo -e "\n${WHITE}🚀 PRIMEROS PASOS:${NC}"
    echo -e "${YELLOW}  1. Iniciar el transcriptor:${NC}"
    echo -e "     ${CYAN}freepbx-transcriptor start${NC}"
    echo -e "\n${YELLOW}  2. Ver estado:${NC}"
    echo -e "     ${CYAN}freepbx-transcriptor status${NC}"
    echo -e "\n${YELLOW}  3. Ver logs en tiempo real:${NC}"
    echo -e "     ${CYAN}freepbx-transcriptor logs${NC}"
    echo -e "     ${CYAN}tail -f /var/log/freepbx-transcriptor.log${NC}"
    echo -e "\n${YELLOW}  4. Probar PocketBase:${NC}"
    echo -e "     ${CYAN}freepbx-transcriptor pocketbase-test${NC}"
    
    echo -e "\n${WHITE}🔧 INSTALAR COMO SERVICIO (Opcional):${NC}"
    echo -e "     ${CYAN}freepbx-transcriptor install-service${NC}"
    echo -e "     ${CYAN}systemctl start freepbx-transcriptor${NC}"
    echo -e "     ${CYAN}systemctl enable freepbx-transcriptor${NC}"
    
    echo -e "\n${WHITE}📞 CONFIGURACIÓN:${NC}"
    echo -e "${GREEN}  📧 Email origen: ${EMAIL_USUARIO}${NC}"
    echo -e "${GREEN}  📬 Email destino: ${EMAIL_DESTINO}${NC}"
    echo -e "${GREEN}  🎙️ Modelo OpenAI: whisper-1${NC}"
    echo -e "${GREEN}  📁 Carpeta monitoreada: /var/spool/asterisk/monitor${NC}"
    echo -e "${GREEN}  🗄️ PocketBase: ${POCKETBASE_URL}${NC}"
    echo -e "${GREEN}  👤 Admin PocketBase: ${POCKETBASE_EMAIL}${NC}"
    
    echo -e "\n${WHITE}🗄️ POCKETBASE INTEGRACIÓN:${NC}"
    echo -e "${GREEN}  ✅ Colección 'transcripciones' se crea automáticamente${NC}"
    echo -e "${GREEN}  ✅ Todas las transcripciones se guardan en BD${NC}"
    echo -e "${GREEN}  ✅ Metadatos completos almacenados${NC}"
    echo -e "${GREEN}  ✅ Estado de email tracking${NC}"
    echo -e "${GREEN}  ✅ API REST disponible para integraciones${NC}"
    
    echo -e "\n${WHITE}🌐 ACCESO A POCKETBASE:${NC}"
    echo -e "     ${CYAN}Admin Panel: ${POCKETBASE_URL}/_/${NC}"
    echo -e "     ${CYAN}API: ${POCKETBASE_URL}/api/collections/transcripciones/records${NC}"
    
    echo -e "\n${WHITE}💡 AYUDA:${NC}"
    echo -e "     ${CYAN}freepbx-transcriptor${NC} (sin parámetros para ver ayuda)"
    echo -e "     ${CYAN}cat ${INSTALL_DIR}/README.md${NC} (documentación completa)"
    
    echo -e "\n${WHITE}🎉 ¡EL SISTEMA ESTÁ LISTO PARA USAR!${NC}"
    echo -e "${WHITE}Las transcripciones se guardarán automáticamente en PocketBase.${NC}"
    echo -e "${WHITE}Podrás buscar, filtrar y analizar todas las llamadas desde la BD.${NC}"
}

# =========================================================================
# FLUJO PRINCIPAL DE INSTALACIÓN
# =========================================================================

main() {
    # Verificar sistema
    verificar_sistema
    
    # Instalar dependencias
    instalar_dependencias
    
    # Configurar credenciales
    configurar_credenciales
    
    # Crear directorio
    crear_directorio_instalacion
    
    # Crear transcriptor
    crear_transcriptor
    
    # Aplicar configuración
    aplicar_configuracion
    
    # Probar configuración
    probar_configuracion
    
    # Crear scripts de gestión
    crear_scripts_gestion
    
    # Crear documentación
    crear_documentacion
    
    # Mostrar resumen
    mostrar_resumen
}

# Ejecutar instalación
main "$@"
