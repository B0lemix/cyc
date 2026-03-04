@echo off
setlocal

set PORT=8743
set FILE=dashboard_v3.3 - copia.html

:: Comprueba si el puerto ya esta en uso (servidor ya corriendo)
netstat -ano | findstr ":%PORT% " >nul 2>&1
if %errorlevel% equ 0 (
    echo Servidor ya activo en puerto %PORT%. Abriendo navegador...
    start "" "http://localhost:%PORT%/%FILE%"
    exit /b 0
)

echo Iniciando servidor local en http://localhost:%PORT%
echo (Cierra esta ventana para detener el servidor)
echo.

:: Abre el navegador tras 1 segundo (da tiempo a que el servidor arranque)
start "" cmd /c "timeout /t 1 /nobreak >nul && start http://localhost:%PORT%/%FILE%"

:: Inicia el servidor HTTP con Python (bloquea hasta cerrar ventana)
python -m http.server %PORT% --directory "%~dp0"
