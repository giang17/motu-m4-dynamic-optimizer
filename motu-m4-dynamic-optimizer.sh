#!/bin/bash

# MOTU M4 Dynamic Optimizer v4 - Hybrid-Strategie (Stabilität-optimiert)
# P-Cores auf Performance, Background E-Cores auf Powersave, IRQ E-Cores auf Performance

LOG_FILE="/var/log/motu-m4-optimizer.log"
STATE_FILE="/var/run/motu-m4-state"

# CPU-Zuweisungen für Process-Pinning (bleibt bestehen)
IRQ_CPUS="14-19"        # E-Cores für IRQ-Handling (stabile Latenz)
AUDIO_MAIN_CPUS="6-7"   # P-Cores für JACK/PipeWire Hauptprozesse
DAW_CPUS="0-5"          # P-Cores für DAW/Plugins (maximale Performance)
BACKGROUND_CPUS="8-13"  # E-Cores für Audio-Background-Tasks

DEFAULT_GOVERNOR="powersave"

# Vereinheitlichte Audio-Prozess-Liste für alle Optimierungen
# Diese zentrale Liste wird von allen Audio-Optimierungsfunktionen verwendet:
# - optimize_audio_process_affinity() für CPU-Pinning und RT-Prioritäten
# - reset_audio_process_affinity() für das Zurücksetzen der Optimierungen
# - Status-Monitoring für die Prozessübersicht
AUDIO_PROCESSES=(
    # Audio-Engines und -Services (werden separat auf AUDIO_MAIN_CPUS behandelt)
    "jackd" "pipewire" "pipewire-pulse"

    # DAWs und Haupt-Audio-Software (DAW_CPUS + RT-Priorität 70)
    "bitwig-studio" "reaper" "ardour" "studio" "cubase"
    "qtractor" "rosegarden" "renoise" "FL64.exe" "EZmix 3.exe"

    # Synthesizer und Klangerzeuger (DAW_CPUS + RT-Priorität 70)
    "yoshimi" "pianoteq" "organteq" "grandorgue" "aeolus"
    "zynaddsubfx" "qsynth" "fluidsynth" "bristol" "M1.exe" "ARP 2600" "Polisix.exe" "EP-1.exe" "VOX Super Conti"
    "legacycell.exe" "wavestate nativ" "WAVESTATION.exe" "opsix_native.ex" "modwave native." "ARP ODYSSEY"
    "TRITON.exe" "TRITON_Extreme." "EZkeys 2.exe" "EZbass.exe"
    "AAS Player.exe" "Lounge Lizard S"

    # Drums und Percussion (DAW_CPUS + RT-Priorität 70)
    "hydrogen" "drumgizmo" "EZdrummer 3.exe"

    # Plugin-Hosts und Audio-Tools (DAW_CPUS + RT-Priorität 70)
    "carla" "jalv" "lv2host" "lv2rack" "jack-rack"
    "calf" "guitarix" "rakarrack" "klangfalter"

    # Audio-Editoren (DAW_CPUS + RT-Priorität 70)
    "musescore"
)

# Ermittle aktuelle JACK-Settings
get_jack_settings() {
    local bufsize="unknown"
    local samplerate="unknown"
    local nperiods="unknown"
    local jack_status="❌ Nicht aktiv"

    # Ermittle den ursprünglichen User, falls Script als root via sudo läuft
    local original_user=""
    if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        original_user="$SUDO_USER"
    elif [ "$EUID" -ne 0 ]; then
        original_user="$(whoami)"
    fi

    # Prüfe ob JACK läuft UND M4 verfügbar ist
    if pgrep -x "jackd" > /dev/null 2>&1 || pgrep -x "jackdbus" > /dev/null 2>&1; then
        # JACK-Prozess läuft, aber prüfe auch M4-Verfügbarkeit
        local motu_available="false"
        if ls /proc/asound/*/id 2>/dev/null | xargs cat 2>/dev/null | grep -q M4; then
            motu_available="true"
        fi

        if [ "$motu_available" = "true" ]; then
            jack_status="✅ Aktiv"
        else
            jack_status="⚠️ Läuft (M4 nicht verfügbar)"
        fi

        # Funktion zum Ausführen von JACK-Commands im User-Kontext
        run_jack_command() {
            local cmd="$1"
            if [ -n "$original_user" ] && [ "$EUID" -eq 0 ]; then
                # Als root: Verwende sudo -u um im User-Kontext zu laufen
                sudo -u "$original_user" "$cmd" 2>/dev/null || echo "unknown"
            else
                # Als normaler User: Direkt ausführen
                "$cmd" 2>/dev/null || echo "unknown"
            fi
        }

        # Versuche JACK-Parameter zu ermitteln
        if command -v jack_bufsize &> /dev/null; then
            bufsize=$(run_jack_command "jack_bufsize")
        fi

        if command -v jack_samplerate &> /dev/null; then
            samplerate=$(run_jack_command "jack_samplerate")
        fi

        if command -v jack_control &> /dev/null; then
            # Extrahiere nperiods-Wert aus der Form "uint:set:2:3" - nehme den letzten Wert
            if [ -n "$original_user" ] && [ "$EUID" -eq 0 ]; then
                nperiods=$(sudo -u "$original_user" jack_control dp 2>/dev/null | grep nperiods | awk -F':' '{print $NF}' | tr -d ')' || echo "unknown")
            else
                nperiods=$(jack_control dp 2>/dev/null | grep nperiods | awk -F':' '{print $NF}' | tr -d ')' || echo "unknown")
            fi
        fi

        # Fallback: Falls alle JACK-Commands fehlschlagen, aber Prozess läuft
        if [ "$bufsize" = "unknown" ] && [ "$samplerate" = "unknown" ] && [ -n "$original_user" ]; then
            if [ "$jack_status" = "✅ Aktiv" ]; then
                jack_status="⚠️ Aktiv (User-Session)"
            fi
        fi
    fi

    echo "$jack_status|$bufsize|$samplerate|$nperiods"
}

# Generiere dynamische Xrun-Empfehlungen basierend auf aktuellen JACK-Settings
get_dynamic_xrun_recommendations() {
    local current_xruns=$1
    local severity=$2  # "perfect", "mild", "severe"

    # Ermittle aktuelle JACK-Settings
    local jack_info=$(get_jack_settings)
    local jack_status=$(echo "$jack_info" | cut -d'|' -f1)
    local bufsize=$(echo "$jack_info" | cut -d'|' -f2)
    local samplerate=$(echo "$jack_info" | cut -d'|' -f3)
    local nperiods=$(echo "$jack_info" | cut -d'|' -f4)

    # Formatiere aktuelle Settings für Anzeige
    local settings_info=""
    if [ "$jack_status" = "✅ Aktiv" ]; then
        settings_info="Aktuell: ${bufsize}@${samplerate}Hz"
        if [ "$nperiods" != "unknown" ]; then
            settings_info="$settings_info, $nperiods periods"
        fi
    else
        settings_info="JACK nicht aktiv"
    fi

    case "$severity" in
        "perfect")
            echo "   🎉 Perfekte Audio-Performance - Keine Xruns!"
            echo "   💡 $settings_info läuft optimal stabil"
            ;;
        "mild")
            echo "   🟡 Gelegentliche Audio-Probleme - Noch im akzeptablen Bereich"
            if [ "$jack_status" = "✅ Aktiv" ] && [ "$bufsize" != "unknown" ]; then
                # Dynamische Empfehlung basierend auf aktuellem Buffer
                if [ "$bufsize" -le 128 ]; then
                    echo "   💡 Bei häufigeren Problemen: Buffer von $bufsize auf 256 Samples erhöhen"
                elif [ "$bufsize" -le 256 ]; then
                    echo "   💡 Bei häufigeren Problemen: Buffer von $bufsize auf 512 Samples erhöhen"
                else
                    echo "   💡 Buffer bereits hoch ($bufsize) - prüfen Sie CPU-Last oder Samplerate"
                fi

                # Periods-Empfehlung
                if [ "$nperiods" != "unknown" ] && [ "$nperiods" -eq 2 ]; then
                    echo "   💡 Erwägen Sie 3 periods statt $nperiods für mehr Stabilität"
                fi
            else
                echo "   💡 $settings_info - Starten Sie JACK für spezifische Empfehlungen"
            fi
            ;;
        "severe")
            echo "   🔴 Häufige Audio-Probleme erkannt ($current_xruns Xruns)"
            if [ "$jack_status" = "✅ Aktiv" ] && [ "$bufsize" != "unknown" ]; then
                # Aggressivere Empfehlungen bei schweren Problemen
                if [ "$bufsize" -le 64 ]; then
                    echo "   💡 Sofort-Maßnahme: Buffer von $bufsize auf 256+ Samples erhöhen"
                elif [ "$bufsize" -le 128 ]; then
                    echo "   💡 Empfehlung: Buffer von $bufsize auf 512 Samples erhöhen"
                elif [ "$bufsize" -le 256 ]; then
                    echo "   💡 Buffer von $bufsize auf 1024 Samples oder höher erhöhen"
                else
                    echo "   💡 Buffer bereits sehr hoch ($bufsize) - System-Optimierung nötig"
                fi

                # Samplerate-Empfehlung
                if [ "$samplerate" != "unknown" ] && [ "$samplerate" -gt 48000 ]; then
                    echo "   💡 Oder Samplerate von ${samplerate}Hz auf 48kHz reduzieren für mehr Stabilität"
                fi

                # Periods-Empfehlung
                if [ "$nperiods" != "unknown" ] && [ "$nperiods" -eq 2 ]; then
                    echo "   💡 Wichtig: 3 periods statt $nperiods verwenden für bessere Latenz-Toleranz"
                fi
            else
                echo "   💡 $settings_info - Starten Sie JACK für detaillierte Empfehlungen"
                echo "   💡 Generell: Höhere Buffer-Größen (256+ Samples) oder niedrigere Samplerate"
            fi
            ;;
    esac
}

# Logging-Funktion mit Fallback für normale User
log_message() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') - $1"

    # Versuche in System-Log zu schreiben
    if echo "$message" >> "$LOG_FILE" 2>/dev/null; then
        echo "$message"
    else
        # Fallback für normale User
        local user_log="$HOME/.local/share/motu-m4-optimizer.log"
        mkdir -p "$(dirname "$user_log")" 2>/dev/null
        echo "$message" | tee -a "$user_log"

        # Einmalige Warnung über Log-Location
        if [ ! -f "$HOME/.local/share/.motu-log-warning-shown" ]; then
            echo "ℹ️  Log wird gespeichert in: $user_log"
            touch "$HOME/.local/share/.motu-log-warning-shown" 2>/dev/null
        fi
    fi
}

# Prüfe ob CPUs isoliert sind
check_cpu_isolation() {
    local isolated_cpus=""
    if [ -e "/sys/devices/system/cpu/isolated" ]; then
        isolated_cpus=$(cat /sys/devices/system/cpu/isolated)
    fi

    # Prüfe auch Kernel-Boot-Parameter
    local kernel_isolation=""
    if grep -q "isolcpus=" /proc/cmdline; then
        kernel_isolation=$(grep -o "isolcpus=[0-9,-]*" /proc/cmdline | cut -d= -f2)
    fi

    log_message "📊 CPU-Isolation Status:"
    log_message "  Sys-Isolation: '$isolated_cpus'"
    log_message "  Kernel-Param: '$kernel_isolation'"

    echo "$isolated_cpus|$kernel_isolation"
}

# Prüfe ob MOTU M4 angeschlossen ist
check_motu_m4() {
    local motu_found=false

    # Prüfe ALSA-Karten
    for card in /proc/asound/card*; do
        if [ -e "$card/id" ]; then
            card_id=$(cat "$card/id" 2>/dev/null)
            if [ "$card_id" = "M4" ]; then
                motu_found=true
                break
            fi
        fi
    done

    # Zusätzliche USB-Prüfung
    if ! $motu_found; then
        if lsusb | grep -q "Mark of the Unicorn"; then
            motu_found=true
        fi
    fi

    echo $motu_found
}

# Xrun-Statistiken sammeln
get_xrun_stats() {
    local jack_xruns=0
    local pipewire_xruns=0
    local jack_messages=0
    local total_xruns=0

    # Echte JACK Xrun-Erkennung mit jack_test (falls JACK läuft)
    if pgrep -x "jackd\|jackdbus" > /dev/null 2>&1; then
        # Methode 1: jack_test für echte Xrun-Statistiken
        if command -v jack_test &> /dev/null; then
            # jack_test -t 5 läuft 5 Sekunden und meldet Xruns
            jack_test_output=$(timeout 7 jack_test -t 5 2>&1 || echo "timeout")
            jack_xruns=$(echo "$jack_test_output" | grep -i "xrun\|late\|early" | wc -l || echo "0")

            # Fallback: Suche nach "%" Werten die Timing-Probleme anzeigen
            if [ "$jack_xruns" -eq 0 ]; then
                timing_issues=$(echo "$jack_test_output" | grep -E "[1-9][0-9]*\.[0-9]*%" | wc -l || echo "0")
                jack_xruns=$timing_issues
            fi
        fi

        # Methode 2: jack_simple_client für Live-Test (nur bei 0 Xruns)
        if command -v jack_simple_client &> /dev/null && [ "$jack_xruns" -eq 0 ]; then
            # Kurzer Test-Client um Xruns zu provozieren/erkennen
            jack_client_test=$(timeout 3 jack_simple_client 2>&1 | grep -i "xrun\|buffer\|late" | wc -l || echo "0")
            jack_xruns=$((jack_xruns + jack_client_test))
        fi

        # Methode 3: JACK-Logs aus journalctl der letzten 2 Minuten
        if command -v journalctl &> /dev/null; then
            jack_log_xruns=$(journalctl --since "2 minutes ago" --no-pager -q 2>/dev/null | grep -iE "(jack|qjackctl).*(xrun|underrun|delay.*exceeded|timeout|late)" | wc -l || echo "0")
            jack_xruns=$((jack_xruns + jack_log_xruns))
        fi

        # Methode 4: QJackCtl-spezifische Xrun-Erkennung
        if pgrep -x "qjackctl" > /dev/null 2>&1; then
            qjackctl_logs=$(journalctl --since "1 minute ago" --no-pager -q 2>/dev/null | grep -i "qjackctl.*xrun.*count\|jack.*xrun.*detected" | wc -l || echo "0")
            jack_xruns=$((jack_xruns + qjackctl_logs))
        fi
    fi

    # PipeWire Xrun-Erkennung über JACK-Tunnel-Logs (erweitert)
    if pgrep -x "pipewire" > /dev/null 2>&1; then
        # PipeWire-JACK-Tunnel Xruns (spezifisch für dein Setup)
        if command -v journalctl &> /dev/null; then
            # Suche nach "mod.jack-tunnel: Xrun" Nachrichten der letzten 2 Minuten
            pipewire_xruns=$(journalctl --since "2 minutes ago" --no-pager -q 2>/dev/null | grep -i "mod\.jack-tunnel.*xrun\|pipewire.*xrun\|pipewire.*drop\|pipewire.*underrun" | wc -l || echo "0")
        fi
    fi

    # Gesamtzahl berechnen
    total_xruns=$((jack_xruns + pipewire_xruns))

    echo "jack:$jack_xruns|pipewire:$pipewire_xruns|total:$total_xruns"
}

# Live JACK Xrun Counter mit besserer PipeWire-JACK-Tunnel Erkennung
get_live_jack_xruns() {
    local xrun_count=0
    local pipewire_xruns=0

    # Priorität: PipeWire-JACK-Tunnel Xruns (da diese bei dir funktionieren)
    if pgrep -x "pipewire" > /dev/null 2>&1; then
        # PipeWire-JACK-Tunnel Xruns der letzten 10 Sekunden (Live-Erkennung)
        if command -v journalctl &> /dev/null; then
            pipewire_xruns=$(journalctl --since "10 seconds ago" --no-pager -q 2>/dev/null | grep -i "mod\.jack-tunnel.*xrun" | wc -l || echo "0")
            xrun_count=$((xrun_count + pipewire_xruns))
        fi
    fi

    # JACK direkte Xruns (falls JACK läuft)
    if pgrep -x "jackd\|jackdbus" > /dev/null 2>&1; then
        # JACK-Server-Messages der letzten 15 Sekunden
        if command -v journalctl &> /dev/null; then
            jack_recent=$(journalctl --since "15 seconds ago" --no-pager -q 2>/dev/null | grep -iE "jack.*(xrun|buffer.*late|delay.*exceeded|timeout)" | wc -l || echo "0")
            xrun_count=$((xrun_count + jack_recent))
        fi

        # QJackCtl/Patchance spezifische Logs
        if pgrep -x "qjackctl" > /dev/null 2>&1; then
            qjackctl_live=$(journalctl --since "15 seconds ago" --no-pager -q 2>/dev/null | grep -iE "(qjackctl|patchance).*(xrun|late|timeout)" | wc -l || echo "0")
            xrun_count=$((xrun_count + qjackctl_live))
        fi
    fi

    echo "$xrun_count"
}

# Xrun-Monitoring über Systemlogs und JACK-Messages
get_system_xruns() {
    local recent_xruns=0
    local severe_xruns=0
    local jack_messages=0

    # Suche in den letzten 5 Minuten nach Audio-Xruns
    if command -v journalctl &> /dev/null; then
        # JACK-spezifische Nachrichten
        jack_messages=$(journalctl --since "5 minutes ago" -u "*jack*" 2>/dev/null | grep -i "xrun\|delay\|timeout" | wc -l || echo "0")

        # Allgemeine Audio-Probleme
        recent_xruns=$(journalctl --since "5 minutes ago" 2>/dev/null | grep -iE "(audio|sound).*(xrun|underrun|overrun|drop|timeout|delay)" | wc -l || echo "0")

        # Hardware-Fehler
        severe_xruns=$(journalctl --since "5 minutes ago" 2>/dev/null | grep -iE "(usb|audio).*(error|fail|disconnect|reset)" | wc -l || echo "0")
    fi

    # Dmesg für USB-Audio-Probleme (mit sudo fallback)
    if command -v dmesg &> /dev/null; then
        usb_audio_errors=$(dmesg 2>/dev/null | tail -100 | grep -iE "(usb|audio).*(error|xrun|underrun)" | wc -l 2>/dev/null || echo "0")
        if [ "$usb_audio_errors" = "0" ] && [ "$EUID" -eq 0 ]; then
            usb_audio_errors=$(dmesg | tail -100 | grep -iE "(usb|audio).*(error|xrun|underrun)" | wc -l 2>/dev/null || echo "0")
        fi
        severe_xruns=$((severe_xruns + usb_audio_errors))
    fi

    echo "recent:$recent_xruns|severe:$severe_xruns|jack_msg:$jack_messages"
}

# Audio-Prozess-Affinität auf optimale P-Cores setzen
optimize_audio_process_affinity() {
    log_message "🎯 Setze Audio-Prozess-Affinität auf optimale P-Cores..."

    # JACK-Prozesse auf dedizierte P-Cores (6-7)
    for pid in $(ps -eo pid,comm | grep -E "^[[:space:]]*[0-9]+[[:space:]]+jackd" | awk '{print $1}'); do
        if command -v taskset &> /dev/null; then
            taskset -cp $AUDIO_MAIN_CPUS $pid 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  JACK Prozess $pid auf P-Cores $AUDIO_MAIN_CPUS gepinnt"
            fi
        fi

        # Höchste Echtzeit-Priorität für JACK
        if command -v chrt &> /dev/null; then
            chrt -f -p 99 $pid 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  JACK Prozess $pid auf Echtzeit-Priorität 99 gesetzt"
            fi
        fi
    done

    # PipeWire-Prozesse auf P-Cores
    for pid in $(ps -eo pid,comm | grep -E "pipewire$" | awk '{print $1}'); do
        if command -v taskset &> /dev/null; then
            taskset -cp $AUDIO_MAIN_CPUS $pid 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  PipeWire Prozess $pid auf P-Cores $AUDIO_MAIN_CPUS gepinnt"
            fi
        fi
        if command -v chrt &> /dev/null; then
            chrt -f -p 85 $pid 2>/dev/null
        fi
    done

    # PipeWire-Pulse auf P-Cores
    for pid in $(ps -eo pid,comm | grep -E "pipewire-pulse" | awk '{print $1}'); do
        if command -v taskset &> /dev/null; then
            taskset -cp $AUDIO_MAIN_CPUS $pid 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  PipeWire-Pulse Prozess $pid auf P-Cores $AUDIO_MAIN_CPUS gepinnt"
            fi
        fi
        if command -v chrt &> /dev/null; then
            chrt -f -p 80 $pid 2>/dev/null
        fi
    done

    # Vereinheitlichte Audio-Prozess-Optimierung
    # Behandelt alle DAWs, Synthesizer, Plugin-Hosts und Audio-Tools einheitlich
    # JACK/PipeWire werden separat auf AUDIO_MAIN_CPUS (6-7) behandelt
    for audio_app in "${AUDIO_PROCESSES[@]}"; do
        # Skip JACK/PipeWire hier - die werden separat auf AUDIO_MAIN_CPUS behandelt
        if [[ "$audio_app" =~ ^(jackd|pipewire|pipewire-pulse)$ ]]; then
            continue
        fi

        for pid in $(ps -eo pid,comm --no-headers | awk -v pattern="^$audio_app$" 'tolower($2) ~ tolower(pattern) {print $1}'); do
            # CPU-Affinität auf DAW P-Cores (0-5) setzen für maximale Single-Thread-Performance
            if command -v taskset &> /dev/null; then
                taskset -cp $DAW_CPUS $pid 2>/dev/null
                if [ $? -eq 0 ]; then
                    log_message "  Audio-App ($audio_app) Prozess $pid auf P-Cores $DAW_CPUS gepinnt"
                fi
            fi

            # RT-Priorität 70 für alle Audio-Software (niedrigere Priorität als JACK)
            if command -v chrt &> /dev/null; then
                chrt -f -p 70 $pid 2>/dev/null
            fi
        done
    done
}

# Audio-Prozess-Affinität zurücksetzen
# Verwendet die gleiche vereinheitlichte AUDIO_PROCESSES Liste wie optimize_audio_process_affinity()
reset_audio_process_affinity() {
    log_message "🔄 Setze Audio-Prozess-Affinität zurück..."

    # Alle Audio-Prozesse auf alle CPUs zurücksetzen - Verwendung der vereinheitlichten Liste
    for process in "${AUDIO_PROCESSES[@]}"; do
        for pid in $(ps -eo pid,comm --no-headers | awk -v pattern="^$process$" 'tolower($2) ~ tolower(pattern) {print $1}'); do
            if command -v taskset &> /dev/null; then
                taskset -cp 0-19 $pid 2>/dev/null
                if [ $? -eq 0 ]; then
                    log_message "  Prozess $process ($pid) auf alle CPUs (0-19) zurückgesetzt"
                fi
            fi

            # Priorität zurücksetzen (normale Scheduling)
            if command -v chrt &> /dev/null; then
                chrt -o -p 0 $pid 2>/dev/null
            fi
        done
    done
}

# Aktiviere Audio-Optimierungen - Hybrid-Strategie (Stabilität-optimiert)
activate_audio_optimizations() {
    log_message "🎵 MOTU M4 erkannt - Aktiviere Hybrid Audio-Optimierungen..."
    log_message "🏗️  Strategie: P-Cores(0-7) Performance, Background E-Cores(8-13) Powersave, IRQ E-Cores(14-19) Performance"

    # P-Cores für Audio-Processing optimieren (0-7)
    log_message "🚀 Optimiere P-Cores (0-7) für Audio-Processing..."
    for cpu in {0..7}; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            echo performance > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  P-Core CPU $cpu: Governor auf 'performance' gesetzt"
            fi
        fi

        # P-Core spezifische Optimierungen
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq" ]; then
            max_freq=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq" 2>/dev/null)
            if [ -n "$max_freq" ]; then
                echo $max_freq > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq" 2>/dev/null
                log_message "  P-Core CPU $cpu: Min-Frequenz auf Maximum gesetzt"
            fi
        fi
    done

    # Background E-Cores auf Powersave lassen (8-13) - Reduziert Störungen
    log_message "🔋 Lasse Background E-Cores (8-13) auf Powersave für Stabilität..."
    for cpu in {8..13}; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            current_governor=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor")
            if [ "$current_governor" != "$DEFAULT_GOVERNOR" ]; then
                echo "$DEFAULT_GOVERNOR" > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" 2>/dev/null
                if [ $? -eq 0 ]; then
                    log_message "  Background E-Core CPU $cpu: Governor auf '$DEFAULT_GOVERNOR' gesetzt"
                fi
            fi
        fi
    done

    # IRQ E-Cores auf Performance optimieren (14-19)
    log_message "⚡ Optimiere IRQ E-Cores (14-19) für stabile Latenz..."
    for cpu in {14..19}; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            echo performance > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  IRQ E-Core CPU $cpu: Governor auf 'performance' gesetzt"
            fi
        fi
    done

    # USB-Controller IRQs auf E-Cores setzen (bewährte Strategie beibehalten)
    log_message "🎯 USB-Controller IRQs auf E-Cores (14-19) für stabile Latenz..."
    USB_IRQS=$(cat /proc/interrupts | grep "xhci_hcd" | awk '{print $1}' | tr -d ':')
    for IRQ in $USB_IRQS; do
        if [ -e "/proc/irq/$IRQ/smp_affinity_list" ]; then
            echo "$IRQ_CPUS" > "/proc/irq/$IRQ/smp_affinity_list" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  USB-Controller IRQ $IRQ auf E-Cores $IRQ_CPUS gesetzt"
            fi

            # IRQ-Optimierungen
            if [ -e "/proc/irq/$IRQ/threading" ]; then
                echo "forced" > "/proc/irq/$IRQ/threading" 2>/dev/null
            fi
            if [ -e "/proc/irq/$IRQ/balance_disabled" ]; then
                echo 1 > "/proc/irq/$IRQ/balance_disabled" 2>/dev/null
            fi
        fi
    done

    # Fallback für bekannte IRQs
    for IRQ in 156 176; do
        if [ -e "/proc/irq/$IRQ/smp_affinity_list" ]; then
            echo "$IRQ_CPUS" > "/proc/irq/$IRQ/smp_affinity_list" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  Fallback: IRQ $IRQ auf E-Cores $IRQ_CPUS gesetzt"
            fi
        fi
    done

    # Audio-IRQs auf E-Cores setzen (für niedrigere Latenz)
    log_message "🔊 Audio-IRQs auf E-Cores (14-19) für optimale Latenz..."
    AUDIO_IRQS=$(cat /proc/interrupts | grep -i "snd\|audio" | awk '{print $1}' | tr -d ':')
    for IRQ in $AUDIO_IRQS; do
        if [ -e "/proc/irq/$IRQ/smp_affinity_list" ]; then
            current_affinity=$(cat "/proc/irq/$IRQ/smp_affinity_list")
            if [ "$current_affinity" != "$IRQ_CPUS" ]; then
                echo "$IRQ_CPUS" > "/proc/irq/$IRQ/smp_affinity_list" 2>/dev/null
                if [ $? -eq 0 ]; then
                    log_message "  Audio IRQ $IRQ auf E-Cores $IRQ_CPUS gesetzt (war: $current_affinity)"
                fi
            fi

            # Audio-IRQ Balance optimieren
            if [ -e "/proc/irq/$IRQ/balance_disabled" ]; then
                echo 1 > "/proc/irq/$IRQ/balance_disabled" 2>/dev/null
            fi
        fi
    done

    # Audio-Prozess-Affinität auf optimale P-Cores setzen
    optimize_audio_process_affinity

    # MOTU M4 USB-Optimierungen
    optimize_motu_usb_settings

    # Kernel-Parameter optimieren
    optimize_kernel_parameters

    # Erweiterte Audio-Optimierungen
    optimize_advanced_audio_settings

    echo "optimized" > "$STATE_FILE"
    log_message "✅ Hybrid Audio-Optimierungen aktiviert - Stabilität und Performance optimal!"
}

# Deaktiviere Audio-Optimierungen - Zurück zu Standard
deactivate_audio_optimizations() {
    log_message "🔧 MOTU M4 nicht erkannt - Setze auf Standard-Konfiguration zurück..."

    # Audio-relevante CPUs zurücksetzen (P-Cores + IRQ E-Cores)
    log_message "🔋 Setze Audio-relevante CPUs auf Standard-Governor..."
    for cpu in {0..7} {14..19}; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            current_governor=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor")
            if [ "$current_governor" = "performance" ]; then
                echo "$DEFAULT_GOVERNOR" > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" 2>/dev/null
                if [ $? -eq 0 ]; then
                    log_message "  CPU $cpu: Governor auf '$DEFAULT_GOVERNOR' zurückgesetzt"
                fi
            fi
        fi

        # Min-Frequenz zurücksetzen
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq" ]; then
            min_freq=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/cpuinfo_min_freq" 2>/dev/null)
            if [ -n "$min_freq" ]; then
                echo $min_freq > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq" 2>/dev/null
            fi
        fi
    done

    # Prozess-Affinität zurücksetzen
    reset_audio_process_affinity

    # USB-Controller IRQs auf alle CPUs verteilen
    USB_IRQS=$(cat /proc/interrupts | grep "xhci_hcd" | awk '{print $1}' | tr -d ':')
    for IRQ in $USB_IRQS; do
        if [ -e "/proc/irq/$IRQ/smp_affinity_list" ]; then
            echo "0-19" > "/proc/irq/$IRQ/smp_affinity_list" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  USB-Controller IRQ $IRQ auf alle CPUs (0-19) zurückgesetzt"
            fi

            # IRQ-Balance wieder aktivieren
            if [ -e "/proc/irq/$IRQ/balance_disabled" ]; then
                echo 0 > "/proc/irq/$IRQ/balance_disabled" 2>/dev/null
            fi
        fi
    done

    # Audio-IRQs auf alle CPUs verteilen
    AUDIO_IRQS=$(cat /proc/interrupts | grep -i "snd\|audio" | awk '{print $1}' | tr -d ':')
    for IRQ in $AUDIO_IRQS; do
        if [ -e "/proc/irq/$IRQ/smp_affinity_list" ]; then
            echo "0-19" > "/proc/irq/$IRQ/smp_affinity_list" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  Audio IRQ $IRQ auf alle CPUs (0-19) zurückgesetzt"
            fi

            # IRQ-Balance wieder aktivieren
            if [ -e "/proc/irq/$IRQ/balance_disabled" ]; then
                echo 0 > "/proc/irq/$IRQ/balance_disabled" 2>/dev/null
            fi
        fi
    done

    # Kernel-Parameter zurücksetzen
    reset_kernel_parameters

    echo "standard" > "$STATE_FILE"
    log_message "✅ Hybrid-Optimierungen deaktiviert, System auf Standard zurückgesetzt"
}

# MOTU M4 USB-Optimierungen
optimize_motu_usb_settings() {
    log_message "🔌 Optimiere MOTU M4 USB-Einstellungen..."

    for usb_device in /sys/bus/usb/devices/*; do
        if [ -e "$usb_device/idVendor" ] && [ -e "$usb_device/idProduct" ]; then
            VENDOR=$(cat "$usb_device/idVendor" 2>/dev/null)
            PRODUCT=$(cat "$usb_device/idProduct" 2>/dev/null)

            if [ "$VENDOR" = "07fd" ] && [ "$PRODUCT" = "000b" ]; then
                log_message "  MOTU M4 USB-Optimierungen: $usb_device"

                if [ -e "$usb_device/power/control" ]; then
                    echo "on" > "$usb_device/power/control"
                    log_message "    Power-Management: always on"
                fi

                if [ -e "$usb_device/power/autosuspend" ]; then
                    echo -1 > "$usb_device/power/autosuspend"
                    log_message "    Autosuspend: deaktiviert"
                fi

                if [ -e "$usb_device/power/autosuspend_delay_ms" ]; then
                    echo -1 > "$usb_device/power/autosuspend_delay_ms"
                    log_message "    Autosuspend-Delay: deaktiviert"
                fi

                # USB-Bulk-Transfer-Optimierungen
                if [ -e "$usb_device/urbnum" ]; then
                    echo 32 > "$usb_device/urbnum" 2>/dev/null
                    if [ $? -eq 0 ]; then
                        log_message "    URB-Anzahl auf 32 erhöht"
                    else
                        log_message "    URB-Optimierung: Keine Berechtigung (normal)"
                    fi
                fi
            fi
        fi
    done
}

# Kernel-Parameter optimieren
optimize_kernel_parameters() {
    log_message "⚙️  Optimiere Kernel-Parameter für Audio..."

    # Real-Time Scheduling
    if [ -e /proc/sys/kernel/sched_rt_runtime_us ]; then
        echo -1 > /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null
        log_message "  RT-Runtime: Unlimited"
    fi

    # Memory Management
    if [ -e /proc/sys/vm/swappiness ]; then
        echo 10 > /proc/sys/vm/swappiness 2>/dev/null
        log_message "  Swappiness: 10"
    fi

    # Audio-spezifische Optimierungen
    if [ -e /proc/sys/kernel/sched_latency_ns ]; then
        echo 1000000 > /proc/sys/kernel/sched_latency_ns 2>/dev/null
        log_message "  Scheduler-Latenz: 1ms"
    fi

    if [ -e /proc/sys/kernel/sched_min_granularity_ns ]; then
        echo 100000 > /proc/sys/kernel/sched_min_granularity_ns 2>/dev/null
        log_message "  Min-Granularität: 0.1ms"
    fi
}

# Kernel-Parameter zurücksetzen
reset_kernel_parameters() {
    log_message "⚙️  Setze Kernel-Parameter zurück..."

    if [ -e /proc/sys/kernel/sched_rt_runtime_us ]; then
        echo 950000 > /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null
        log_message "  RT-Runtime: Standard (950ms)"
    fi

    if [ -e /proc/sys/vm/swappiness ]; then
        echo 60 > /proc/sys/vm/swappiness 2>/dev/null
        log_message "  Swappiness: Standard (60)"
    fi

    if [ -e /proc/sys/kernel/sched_latency_ns ]; then
        echo 6000000 > /proc/sys/kernel/sched_latency_ns 2>/dev/null
        log_message "  Scheduler-Latenz: Standard (6ms)"
    fi

    if [ -e /proc/sys/kernel/sched_min_granularity_ns ]; then
        echo 750000 > /proc/sys/kernel/sched_min_granularity_ns 2>/dev/null
        log_message "  Min-Granularität: Standard (0.75ms)"
    fi
}

# Erweiterte Audio-Optimierungen
optimize_advanced_audio_settings() {
    log_message "🎼 Aktiviere erweiterte Audio-Optimierungen..."

    # USB-Bulk-Transfer-Optimierungen
    if [ -e /sys/module/usbcore/parameters/usbfs_memory_mb ]; then
        echo 256 > /sys/module/usbcore/parameters/usbfs_memory_mb 2>/dev/null
        log_message "  USB-Memory-Buffer: 256MB"
    fi

    # Audio-Subsystem-Optimierungen
    if [ -e /proc/sys/dev/hpet/max-user-freq ]; then
        echo 2048 > /proc/sys/dev/hpet/max-user-freq 2>/dev/null
        log_message "  HPET-Frequenz: 2048Hz"
    fi

    # Network-Interface-Interrupts von Audio-CPUs weglenken
    for netif in /sys/class/net/*/queues/rx-*/rps_cpus; do
        if [ -e "$netif" ]; then
            # Netzwerk-RPS auf E-Cores 8-13 beschränken
            echo "00003f00" > "$netif" 2>/dev/null
        fi
    done
    log_message "  Netzwerk-Interrupts auf Background-E-Cores umgeleitet"
}

# Script-Performance optimieren
optimize_script_performance() {
    local script_pid=$$

    # Script auf Background E-Cores pinnen (8-13)
    if command -v taskset &> /dev/null; then
        taskset -cp $BACKGROUND_CPUS $script_pid 2>/dev/null
        if [ $? -eq 0 ]; then
            log_message "📌 Script selbst auf Background E-Cores $BACKGROUND_CPUS gepinnt"
        fi
    fi

    # Niedrige Priorität für das Script
    if command -v chrt &> /dev/null; then
        chrt -o -p 0 $script_pid 2>/dev/null
        if [ $? -eq 0 ]; then
            log_message "⬇️  Script-Priorität auf niedrig gesetzt"
        fi
    fi

    # I/O-Priorität reduzieren
    if command -v ionice &> /dev/null; then
        ionice -c 3 -p $script_pid 2>/dev/null
        if [ $? -eq 0 ]; then
            log_message "💽 Script I/O-Priorität auf Idle gesetzt"
        fi
    fi
}

# Detaillierte Monitoring-Funktion (erweiterte Informationen)
show_detailed_status() {
    echo "=== MOTU M4 Detailliertes Monitoring ==="
    echo ""

    # Alle MOTU M4 relevanten Informationen
    echo "🎛️  MOTU M4 Hardware-Status:"
    MOTU_CARD=""
    for card in /proc/asound/card*; do
        if [ -e "$card/id" ]; then
            card_id=$(cat "$card/id" 2>/dev/null)
            if [ "$card_id" = "M4" ]; then
                MOTU_CARD=$(basename "$card")
                echo "   Karte: $(cat /proc/asound/$MOTU_CARD/id 2>/dev/null)"
                echo "   Stream-Status: $(cat /proc/asound/$MOTU_CARD/stream0 2>/dev/null)"
                if [ -e "/proc/asound/$MOTU_CARD/usbmixer" ]; then
                    echo "   USB-Mixer: $(head -1 /proc/asound/$MOTU_CARD/usbmixer 2>/dev/null)"
                fi
                break
            fi
        fi
    done

    echo ""
    echo "🔌 USB-Verbindungsdetails:"
    MOTU_USB=$(lsusb | grep "Mark of the Unicorn")
    if [ -n "$MOTU_USB" ]; then
        echo "   $MOTU_USB"
        USB_BUS=$(echo "$MOTU_USB" | awk '{print $2}')
        USB_DEVICE=$(echo "$MOTU_USB" | awk '{print $4}' | tr -d ':')
        echo "   Bus: $USB_BUS, Device: $USB_DEVICE"

        # USB Power Management Details
        for usb_device in /sys/bus/usb/devices/*; do
            if [ -e "$usb_device/idVendor" ] && [ -e "$usb_device/idProduct" ]; then
                VENDOR=$(cat "$usb_device/idVendor" 2>/dev/null)
                PRODUCT=$(cat "$usb_device/idProduct" 2>/dev/null)
                if [ "$VENDOR" = "07fd" ] && [ "$PRODUCT" = "000b" ]; then
                    echo "   Power Control: $(cat "$usb_device/power/control" 2>/dev/null || echo "N/A")"
                    echo "   Autosuspend Delay: $(cat "$usb_device/power/autosuspend_delay_ms" 2>/dev/null || echo "N/A") ms"
                    echo "   USB Speed: $(cat "$usb_device/speed" 2>/dev/null || echo "N/A")"
                    echo "   USB Version: $(cat "$usb_device/version" 2>/dev/null || echo "N/A")"
                    echo "   Max Power: $(cat "$usb_device/bMaxPower" 2>/dev/null || echo "N/A")"
                    break
                fi
            fi
        done
    else
        echo "   MOTU M4 USB-Gerät nicht gefunden!"
    fi

    echo ""
    echo "⚡ Vollständige IRQ-Analyse:"
    echo "   USB-Controller IRQs:"
    cat /proc/interrupts | grep "xhci_hcd" | while read line; do
        irq=$(echo $line | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            affinity=$(cat /proc/irq/$irq/smp_affinity_list)
            threading=$(cat /proc/irq/$irq/threading 2>/dev/null || echo "standard")
            balance=$(cat /proc/irq/$irq/balance_disabled 2>/dev/null || echo "0")
            balance_text="enabled"; [ "$balance" = "1" ] && balance_text="disabled"
            spurious=$(cat /proc/irq/$irq/spurious 2>/dev/null || echo "N/A")
            echo "     IRQ $irq: CPUs=$affinity, Threading=$threading, Balance=$balance_text"
            echo "       $line"
            echo "       Spurious: $spurious"
        fi
    done

    echo ""
    echo "   Audio-spezifische IRQs:"
    cat /proc/interrupts | grep -i "snd\|audio" | while read line; do
        irq=$(echo $line | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            affinity=$(cat /proc/irq/$irq/smp_affinity_list)
            echo "     Audio IRQ $irq: CPUs=$affinity"
            echo "       $line"
        fi
    done

    echo ""
    echo "🎵 Audio-Prozess-Details mit RT-Prioritäten:"
    AUDIO_RT_PROCS=$(ps -eo pid,class,rtprio,ni,comm,cmd | grep -E "FF|RR" | grep -iE "pulse|pipe|jack|audio|pianoteq|organteq|reaper|ardour|bitwig|cubase|logic|ableton|fl_studio|studio|daw|yoshimi|grandorgue|renoise|carla|jalv|qtractor|rosegarden|musescore|zynaddsubfx|qsynth|fluidsynth|bristol|hydrogen|drumgizmo|guitarix|rakarrack" | grep -v "\[.*\]")
    if [ -n "$AUDIO_RT_PROCS" ]; then
        echo "   RT-Audio-Prozesse gefunden:"
        echo "$AUDIO_RT_PROCS" | while read line; do
            echo "     $line"
        done
    else
        echo "   Keine Audio-Prozesse mit RT-Priorität gefunden"
        echo ""
        echo "   Standard Audio-Prozesse (ohne RT):"
        ps -eo pid,class,rtprio,ni,comm,cmd | grep -iE "pulse|pipe|jack|audio|pianoteq|organteq|reaper|ardour|bitwig|cubase|logic|ableton|fl_studio|studio|daw|yoshimi|grandorgue|renoise|carla|jalv|qtractor|rosegarden|musescore|zynaddsubfx|qsynth|fluidsynth|bristol|hydrogen|drumgizmo|guitarix|rakarrack" | grep -v "\[.*\]" | grep -v "grep" | head -5 | while read line; do
            echo "     $line"
        done
    fi

    echo ""
    echo "🖥️  CPU-Details pro Kern:"
    for cpu in {0..19}; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            governor=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor")
            freq_cur=""
            freq_min=""
            freq_max=""
            if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq" ]; then
                freq_khz=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq")
                freq_cur=" @ $(($freq_khz / 1000))MHz"
            fi
            if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq" ]; then
                freq_khz=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq")
                freq_min=" (min: $(($freq_khz / 1000))MHz"
            fi
            if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq" ]; then
                freq_khz=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq")
                freq_max=", max: $(($freq_khz / 1000))MHz)"
            fi

            cpu_type="E-Core"
            role="Background"
            if [ $cpu -le 7 ]; then
                cpu_type="P-Core"
                if [ $cpu -le 5 ]; then
                    role="DAW/Plugins"
                else
                    role="JACK/PipeWire"
                fi
            elif [ $cpu -ge 14 ] && [ $cpu -le 19 ]; then
                role="IRQ-Handling"
            fi

            echo "     CPU $cpu ($cpu_type - $role): $governor$freq_cur$freq_min$freq_max"
        fi
    done

    echo ""
    echo "⚙️  Erweiterte Kernel-Parameter:"
    echo "   RT-Scheduling:"
    if [ -e /proc/sys/kernel/sched_rt_runtime_us ]; then
        rt_runtime=$(cat /proc/sys/kernel/sched_rt_runtime_us)
        if [ "$rt_runtime" = "-1" ]; then
            echo "     RT-Runtime: Unbegrenzt ✓"
        else
            echo "     RT-Runtime: $rt_runtime µs"
        fi
    fi
    if [ -e /proc/sys/kernel/sched_rt_period_us ]; then
        rt_period=$(cat /proc/sys/kernel/sched_rt_period_us)
        echo "     RT-Period: $rt_period µs"
    fi

    echo "   Memory Management:"
    if [ -e /proc/sys/vm/swappiness ]; then
        swappiness=$(cat /proc/sys/vm/swappiness)
        echo "     Swappiness: $swappiness"
    fi
    if [ -e /proc/sys/vm/dirty_ratio ]; then
        dirty_ratio=$(cat /proc/sys/vm/dirty_ratio)
        echo "     Dirty Ratio: $dirty_ratio%"
    fi

    echo ""
    echo "📊 Optimierungs-Erfolgsbilanz:"
    USB_IRQS_OPTIMIZED=0
    USB_IRQS_TOTAL=0
    while read line; do
        irq=$(echo $line | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            USB_IRQS_TOTAL=$((USB_IRQS_TOTAL + 1))
            affinity=$(cat /proc/irq/$irq/smp_affinity_list)
            if [ "$affinity" = "14-19" ]; then
                USB_IRQS_OPTIMIZED=$((USB_IRQS_OPTIMIZED + 1))
            fi
        fi
    done < <(cat /proc/interrupts | grep "xhci_hcd")

    RT_AUDIO_PROCS_COUNT=$(ps -eo pid,class,rtprio,comm,cmd | grep -E "FF|RR" | grep -iE "pulse|pipe|jack|audio|pianoteq|organteq|reaper|ardour|bitwig|cubase|logic|ableton|fl_studio|studio|daw|yoshimi|grandorgue|renoise|carla|jalv|qtractor|rosegarden|musescore|zynaddsubfx|qsynth|fluidsynth|bristol|hydrogen|drumgizmo|guitarix|rakarrack" | grep -v "\[.*\]" | wc -l)

    echo "   ✅ USB-Controller IRQs auf CPUs 14-19: $USB_IRQS_OPTIMIZED/$USB_IRQS_TOTAL"
    echo "   ✅ Audio-Prozesse mit RT-Priorität: $RT_AUDIO_PROCS_COUNT"
    if [ -n "$MOTU_CARD" ]; then
        echo "   ✅ MOTU M4 Hardware: Erkannt als $MOTU_CARD"
    else
        echo "   ❌ MOTU M4 Hardware: Nicht erkannt"
    fi

    echo ""
    echo "🏁 Empfohlene nächste Schritte:"
    if [ $USB_IRQS_OPTIMIZED -eq 0 ]; then
        echo "   🔧 Führen Sie 'sudo $0 once' aus, um IRQ-Optimierungen zu aktivieren"
    fi
    if [ $RT_AUDIO_PROCS_COUNT -eq 0 ]; then
        echo "   🎵 Starten Sie Audio-Software für automatische RT-Priorität-Zuweisung"
    fi
    if [ -z "$MOTU_CARD" ]; then
        echo "   🔌 Überprüfen Sie die MOTU M4 USB-Verbindung"
    fi

    echo ""
    echo "🎵 Detaillierte Audio Xrun-Statistiken:"

    # Xrun-Statistiken sammeln
    xrun_stats=$(get_xrun_stats)
    system_xruns=$(get_system_xruns)
    live_jack_xruns=$(get_live_jack_xruns)

    # Parse Xrun-Daten
    jack_xruns=$(echo "$xrun_stats" | cut -d'|' -f1 | cut -d':' -f2)
    pipewire_xruns=$(echo "$xrun_stats" | cut -d'|' -f2 | cut -d':' -f2)
    total_xruns=$(echo "$xrun_stats" | cut -d'|' -f3 | cut -d':' -f2)

    recent_xruns=$(echo "$system_xruns" | cut -d'|' -f1 | cut -d':' -f2)
    severe_xruns=$(echo "$system_xruns" | cut -d'|' -f2 | cut -d':' -f2)
    jack_messages=$(echo "$system_xruns" | cut -d'|' -f3 | cut -d':' -f2)

    # Status-Icon basierend auf Xruns
    xrun_icon="✅"
    if [ "$total_xruns" -gt 0 ] || [ "$recent_xruns" -gt 0 ] || [ "$live_jack_xruns" -gt 0 ]; then
        xrun_icon="⚠️"
    fi
    if [ "$severe_xruns" -gt 0 ]; then
        xrun_icon="❌"
    fi

    echo "   $xrun_icon JACK Xruns (1min): $jack_xruns"
    echo "   $xrun_icon PipeWire Xruns (1min): $pipewire_xruns"
    echo "   $xrun_icon Live JACK Status: $live_jack_xruns"
    echo "   $xrun_icon JACK Messages (5min): $jack_messages"
    echo "   $xrun_icon System Audio-Probleme (5min): $recent_xruns"
    if [ "$severe_xruns" -gt 0 ]; then
        echo "   ❌ Hardware-Fehler (5min): $severe_xruns"
    fi

    # Dynamische Xrun-Bewertung und Empfehlungen
    total_current_xruns=$((jack_xruns + pipewire_xruns + live_jack_xruns))
    if [ "$total_current_xruns" -eq 0 ] && [ "$recent_xruns" -eq 0 ]; then
        get_dynamic_xrun_recommendations "$total_current_xruns" "perfect"
    elif [ "$total_current_xruns" -lt 5 ] && [ "$severe_xruns" -eq 0 ]; then
        get_dynamic_xrun_recommendations "$total_current_xruns" "mild"
    else
        get_dynamic_xrun_recommendations "$total_current_xruns" "severe"
    fi
    if [ $USB_IRQS_OPTIMIZED -lt $USB_IRQS_TOTAL ] || [ $AUDIO_IRQS_OPTIMIZED -lt $AUDIO_IRQS_TOTAL ]; then
        echo "   ⚡ Führen Sie 'sudo $0 once' aus, um alle IRQ-Optimierungen zu aktivieren"
    fi

    # Zusätzliche Empfehlungen bei anhaltenden Problemen
    detailed_xruns=$(get_system_xruns)
    recent_count=$(echo "$detailed_xruns" | cut -d'|' -f1 | cut -d':' -f2)
    if [ "$recent_count" -gt 3 ]; then
        echo ""
        echo "   🎛️ Zusätzliche Empfehlungen bei anhaltenden Audio-Problemen:"
        get_dynamic_xrun_recommendations "$recent_count" "severe"
    fi
}

# Erweiterte Status-Anzeige
show_status() {
    echo "=== MOTU M4 Dynamic Optimizer v4 Status ==="
    echo ""

    motu_connected=$(check_motu_m4)
    current_state="unknown"

    if [ -e "$STATE_FILE" ]; then
        current_state=$(cat "$STATE_FILE")
    fi

    echo "🎛️  MOTU M4 erkannt: $motu_connected"
    echo "🔄 Aktueller Zustand: $current_state"

    # Aktuelle JACK-Settings anzeigen
    jack_info=$(get_jack_settings)
    jack_status=$(echo "$jack_info" | cut -d'|' -f1)
    bufsize=$(echo "$jack_info" | cut -d'|' -f2)
    samplerate=$(echo "$jack_info" | cut -d'|' -f3)
    nperiods=$(echo "$jack_info" | cut -d'|' -f4)

    echo "🎵 JACK Status: $jack_status"
    if [ "$jack_status" = "✅ Aktiv" ]; then
        echo "   Settings: ${bufsize}@${samplerate}Hz"
        if [ "$nperiods" != "unknown" ]; then
            echo "   Periods: $nperiods"
        fi
    fi
    echo ""

    # Detaillierte MOTU M4 Informationen
    echo "🎵 MOTU M4 Details:"
    MOTU_CARD=""
    for card in /proc/asound/card*; do
        if [ -e "$card/id" ]; then
            card_id=$(cat "$card/id" 2>/dev/null)
            if [ "$card_id" = "M4" ]; then
                MOTU_CARD=$(basename "$card")
                echo "   Karte: $(cat /proc/asound/$MOTU_CARD/id 2>/dev/null)"
                if [ -e "/proc/asound/$MOTU_CARD/stream0" ]; then
                    echo "   Verbindung: $(cat /proc/asound/$MOTU_CARD/stream0 2>/dev/null)"
                fi
                if [ -e "/proc/asound/$MOTU_CARD/usbmixer" ]; then
                    echo "   USB-Details: $(head -1 /proc/asound/$MOTU_CARD/usbmixer 2>/dev/null)"
                fi
                break
            fi
        fi
    done

    if [ -z "$MOTU_CARD" ]; then
        echo "   MOTU M4 Karte nicht in ALSA gefunden"
    fi

    # USB-Gerät Status
    MOTU_USB=$(lsusb | grep "Mark of the Unicorn")
    if [ -n "$MOTU_USB" ]; then
        echo "   USB-Gerät: $MOTU_USB"
        USB_BUS=$(echo "$MOTU_USB" | awk '{print $2}')
        echo "   USB Bus: $USB_BUS"
    else
        echo "   MOTU M4 nicht in USB-Geräten gefunden"
    fi
    echo ""

    # CPU-Isolation prüfen
    isolation_info=$(check_cpu_isolation)
    echo "🔒 CPU-Isolation: $isolation_info"
    echo ""

    echo "🖥️  CPU-Governor Status (Hybrid-Strategie):"
    if [ "$current_state" = "optimized" ]; then
        echo "   🚀 P-Cores: Performance | 🔋 Background E-Cores: Powersave | ⚡ IRQ E-Cores: Performance"
    else
        echo "   🔋 STANDARD: Alle CPUs auf $DEFAULT_GOVERNOR-Governor"
    fi
    echo ""

    echo "   P-Cores (DAW/Plugins: 0-5, JACK/PipeWire: 6-7):"
    for cpu in 0 1 2 3 4 5 6 7; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            governor=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor")
            freq=""
            if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq" ]; then
                freq_khz=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq")
                freq=" @ $(($freq_khz / 1000))MHz"
            fi
            echo "     CPU $cpu: $governor$freq"
        fi
    done

    echo "   E-Cores (Background: 8-13, IRQ-Handling: 14-19):"
    for cpu in 8 9 10 11 12 13 14 15 16 17 18 19; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            governor=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor")
            freq=""
            if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq" ]; then
                freq_khz=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq")
                freq=" @ $(($freq_khz / 1000))MHz"
            fi
            usage=""
            if [ $cpu -ge 14 ] && [ $cpu -le 19 ]; then
                usage=" [IRQ]"
            elif [ $cpu -ge 8 ] && [ $cpu -le 13 ]; then
                usage=" [BG]"
            fi
            echo "     CPU $cpu: $governor$freq$usage"
        fi
    done

    echo ""
    echo "⚡ USB-Controller IRQ-Zuweisungen:"
    USB_IRQS_OPTIMIZED=0
    USB_IRQS_TOTAL=0
    cat /proc/interrupts | grep "xhci_hcd" | while read line; do
        irq=$(echo $line | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            affinity=$(cat /proc/irq/$irq/smp_affinity_list)
            threading=$(cat /proc/irq/$irq/threading 2>/dev/null || echo "standard")
            balance=$(cat /proc/irq/$irq/balance_disabled 2>/dev/null || echo "0")
            balance_text="enabled"; [ "$balance" = "1" ] && balance_text="disabled"

            status_icon="✅"
            if [ "$affinity" != "$IRQ_CPUS" ]; then
                status_icon="⚠️"
            fi
            echo "   $status_icon IRQ $irq: CPUs $affinity, Threading: $threading, Balance: $balance_text"
        fi
    done

    echo ""
    echo "🔊 Audio-IRQs:"
    cat /proc/interrupts | grep -i "snd" | while read line; do
        irq=$(echo $line | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            affinity=$(cat /proc/irq/$irq/smp_affinity_list)
            balance=$(cat /proc/irq/$irq/balance_disabled 2>/dev/null || echo "0")
            balance_text="enabled"; [ "$balance" = "1" ] && balance_text="disabled"

            status_icon="✅"
            if [ "$affinity" != "$IRQ_CPUS" ]; then
                status_icon="⚠️"
            fi
            echo "   $status_icon Audio IRQ $irq: CPUs $affinity, Balance: $balance_text"
        fi
    done

    echo ""
    echo "🎵 Aktive Audio-Prozesse:"

    # Erstelle Liste aller laufenden Audio-Prozesse - Verwendet die vereinheitlichte AUDIO_PROCESSES Liste
    local audio_pattern=""
    for process in "${AUDIO_PROCESSES[@]}"; do
        if [ -z "$audio_pattern" ]; then
            audio_pattern="$process"
        else
            audio_pattern="$audio_pattern|$process"
        fi
    done
    audio_processes=$(ps -eo pid,comm --no-headers | awk -v pattern="^($audio_pattern)$" 'tolower($2) ~ tolower(pattern) {print $1, $2}' | sort -k2)

    if [ -n "$audio_processes" ]; then
        echo "$audio_processes" | while read pid process_name; do
            if [ -n "$pid" ] && [ -n "$process_name" ]; then
                affinity="N/A"
                priority="N/A"
                if command -v taskset &> /dev/null; then
                    affinity=$(taskset -cp $pid 2>/dev/null | cut -d: -f2 | tr -d ' ' || echo "N/A")
                fi
                if command -v chrt &> /dev/null; then
                    priority=$(chrt -p $pid 2>/dev/null | awk '{print $NF}' || echo "N/A")
                fi
                echo "   $process_name ($pid): CPUs=$affinity, Prio=$priority"
            fi
        done
    else
        echo "   Keine Audio-Prozesse gefunden"
    fi

    echo ""
    echo "🔧 Script-Performance:"
    script_pid=$$
    script_affinity="N/A"
    script_priority="N/A"
    script_ionice="N/A"
    if command -v taskset &> /dev/null; then
        script_affinity=$(taskset -cp $script_pid 2>/dev/null | cut -d: -f2 | tr -d ' ' || echo "N/A")
    fi
    if command -v chrt &> /dev/null; then
        script_priority=$(chrt -p $script_pid 2>/dev/null | awk '{print $NF}' || echo "N/A")
    fi
    if command -v ionice &> /dev/null; then
        script_ionice=$(ionice -p $script_pid 2>/dev/null || echo "N/A")
    fi
    echo "   Optimizer ($script_pid): CPUs=$script_affinity, Prio=$script_priority, IO=$script_ionice"

    echo ""
    echo "🔋 MOTU M4 USB Power Management:"
    for usb_device in /sys/bus/usb/devices/*; do
        if [ -e "$usb_device/idVendor" ] && [ -e "$usb_device/idProduct" ]; then
            VENDOR=$(cat "$usb_device/idVendor" 2>/dev/null)
            PRODUCT=$(cat "$usb_device/idProduct" 2>/dev/null)

            if [ "$VENDOR" = "07fd" ] && [ "$PRODUCT" = "000b" ]; then
                echo "   USB-Gerät: $usb_device"
                if [ -e "$usb_device/power/control" ]; then
                    control=$(cat "$usb_device/power/control")
                    echo "   Power Control: $control"
                fi
                if [ -e "$usb_device/power/autosuspend_delay_ms" ]; then
                    delay=$(cat "$usb_device/power/autosuspend_delay_ms")
                    echo "   Autosuspend Delay: $delay ms"
                fi
                if [ -e "$usb_device/speed" ]; then
                    speed=$(cat "$usb_device/speed")
                    echo "   USB Speed: $speed"
                fi
                break
            fi
        fi
    done

    echo ""
    echo "⚙️  Kernel-Parameter Status:"
    if [ -e /proc/sys/kernel/sched_rt_runtime_us ]; then
        rt_runtime=$(cat /proc/sys/kernel/sched_rt_runtime_us)
        if [ "$rt_runtime" = "-1" ]; then
            echo "   RT-Scheduling-Limit: Unbegrenzt ✓"
        else
            echo "   RT-Scheduling-Limit: $rt_runtime µs"
        fi
    fi
    if [ -e /proc/sys/vm/swappiness ]; then
        swappiness=$(cat /proc/sys/vm/swappiness)
        echo "   Swappiness: $swappiness"
    fi

    echo ""
    echo "📊 Optimierungs-Zusammenfassung:"

    # USB IRQ Optimierung prüfen
    USB_IRQS_OPTIMIZED=0
    USB_IRQS_TOTAL=0
    while read line; do
        irq=$(echo $line | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            USB_IRQS_TOTAL=$((USB_IRQS_TOTAL + 1))
            affinity=$(cat /proc/irq/$irq/smp_affinity_list)
            if [ "$affinity" = "$IRQ_CPUS" ]; then
                USB_IRQS_OPTIMIZED=$((USB_IRQS_OPTIMIZED + 1))
            fi
        fi
    done < <(cat /proc/interrupts | grep "xhci_hcd")

    # Audio IRQ Optimierung prüfen
    AUDIO_IRQS_OPTIMIZED=0
    AUDIO_IRQS_TOTAL=0
    while read line; do
        irq=$(echo $line | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            AUDIO_IRQS_TOTAL=$((AUDIO_IRQS_TOTAL + 1))
            affinity=$(cat /proc/irq/$irq/smp_affinity_list)
            if [ "$affinity" = "$IRQ_CPUS" ]; then
                AUDIO_IRQS_OPTIMIZED=$((AUDIO_IRQS_OPTIMIZED + 1))
            fi
        fi
    done < <(cat /proc/interrupts | grep -i "snd")

    RT_AUDIO_PROCS=$(ps -eo pid,class,rtprio,comm,cmd | grep -E "FF|RR" | grep -iE "pulse|pipe|jack|audio|pianoteq|organteq|reaper|ardour|bitwig|cubase|logic|ableton|fl_studio|studio|daw|yoshimi|grandorgue|renoise|carla|jalv|qtractor|rosegarden|musescore|zynaddsubfx|qsynth|fluidsynth|bristol|hydrogen|drumgizmo|guitarix|rakarrack" | grep -v "\[.*\]" | wc -l)

    echo "   USB-Controller IRQs optimiert: $USB_IRQS_OPTIMIZED/$USB_IRQS_TOTAL"
    echo "   Audio IRQs optimiert: $AUDIO_IRQS_OPTIMIZED/$AUDIO_IRQS_TOTAL"
    echo "   Audio-Prozesse mit RT-Priorität: $RT_AUDIO_PROCS"

    # Vollständige Xrun-Status für konsistente Bewertung (wie in detaillierter Ansicht)
    xrun_stats=$(get_xrun_stats)
    system_xruns=$(get_system_xruns)
    live_jack_xruns=$(get_live_jack_xruns)

    # Parse alle Xrun-Daten
    jack_xruns=$(echo "$xrun_stats" | cut -d'|' -f1 | cut -d':' -f2)
    pipewire_xruns=$(echo "$xrun_stats" | cut -d'|' -f2 | cut -d':' -f2)
    recent_xruns=$(echo "$system_xruns" | cut -d'|' -f1 | cut -d':' -f2)
    severe_xruns=$(echo "$system_xruns" | cut -d'|' -f2 | cut -d':' -f2)

    # Gesamte aktuelle Xruns berechnen (wie in detaillierter Ansicht)
    total_current_xruns=$((jack_xruns + pipewire_xruns + live_jack_xruns))

    # JACK-Settings in kompakter Status-Anzeige
    jack_info=$(get_jack_settings)
    jack_status=$(echo "$jack_info" | cut -d'|' -f1)
    bufsize=$(echo "$jack_info" | cut -d'|' -f2)
    samplerate=$(echo "$jack_info" | cut -d'|' -f3)
    nperiods=$(echo "$jack_info" | cut -d'|' -f4)

    echo "   🎵 JACK: $jack_status"
    if [ "$jack_status" = "✅ Aktiv" ]; then
        settings_text="${bufsize}@${samplerate}Hz"
        if [ "$nperiods" != "unknown" ]; then
            settings_text="$settings_text, $nperiods periods"
        fi
        echo "       $settings_text"
    fi

    # Audio-Performance mit konsistenter Bewertung (identisch zur detaillierten Ansicht)
    if [ "$total_current_xruns" -eq 0 ] && [ "$recent_xruns" -eq 0 ]; then
        echo "   ✅ Audio-Performance: Keine Probleme"
        if [ "$jack_status" = "✅ Aktiv" ]; then
            echo "       $settings_text läuft optimal stabil"
        fi
    elif [ "$total_current_xruns" -lt 5 ] && [ "$severe_xruns" -eq 0 ]; then
        echo "   🟡 Audio-Performance: Gelegentliche Probleme ($total_current_xruns Xruns)"
        if [ "$jack_status" = "✅ Aktiv" ] && [ "$bufsize" != "unknown" ]; then
            if [ "$bufsize" -le 128 ]; then
                echo "       💡 Bei häufigeren Problemen: Buffer von $bufsize auf 256 Samples erhöhen"
            elif [ "$bufsize" -le 256 ]; then
                echo "       💡 Bei häufigeren Problemen: Buffer von $bufsize auf 512 Samples erhöhen"
            fi
        fi
    else
        echo "   🔴 Audio-Performance: Häufige Probleme ($total_current_xruns Xruns)"
        if [ "$jack_status" = "✅ Aktiv" ] && [ "$bufsize" != "unknown" ]; then
            if [ "$bufsize" -le 64 ]; then
                echo "       💡 Sofort-Maßnahme: Buffer von $bufsize auf 256+ Samples erhöhen"
            elif [ "$bufsize" -le 128 ]; then
                echo "       💡 Empfehlung: Buffer von $bufsize auf 512 Samples erhöhen"
            elif [ "$bufsize" -le 256 ]; then
                echo "       💡 Buffer von $bufsize auf 1024 Samples oder höher erhöhen"
            else
                echo "       💡 Buffer bereits sehr hoch ($bufsize) - System-Optimierung nötig"
            fi
            if [ "$samplerate" != "unknown" ] && [ "$samplerate" -gt 48000 ]; then
                echo "       💡 Oder Samplerate von ${samplerate}Hz auf 48kHz reduzieren"
            fi
        fi
    fi

    if [ "$severe_xruns" -gt 0 ]; then
        echo "   ❌ Zusätzlich: Hardware-Fehler ($severe_xruns in 5min)"
    fi

    echo ""
    echo "💡 Dynamische Buffer-Empfehlungen basierend auf aktuellen Settings:"
    if [ "$jack_status" = "✅ Aktiv" ] && [ "$bufsize" != "unknown" ] && [ "$samplerate" != "unknown" ]; then
        # Berechne aktuelle Latenz mit Fallback
        if command -v bc &> /dev/null; then
            latency_ms=$(echo "scale=1; $bufsize * 1000 / $samplerate" | bc -l 2>/dev/null || echo "~$(($bufsize * 1000 / $samplerate))")
        else
            latency_ms="~$(($bufsize * 1000 / $samplerate))"
        fi

        echo "   🎯 Aktuell: $bufsize Samples @ ${samplerate}Hz = ${latency_ms}ms"

        # Dynamische Empfehlungen basierend auf Xrun-Situation
        if [ "$total_current_xruns" -gt 20 ]; then
            # Aggressive Empfehlungen bei vielen Xruns
            if [ "$bufsize" -le 256 ]; then
                safe_buffer=1024
                if command -v bc &> /dev/null; then
                    safe_latency=$(echo "scale=1; $safe_buffer * 1000 / $samplerate" | bc -l 2>/dev/null || echo "~$(($safe_buffer * 1000 / $samplerate))")
                else
                    safe_latency="~$(($safe_buffer * 1000 / $samplerate))"
                fi
                echo "   🔴 Probleme erkannt: $safe_buffer Samples = ${safe_latency}ms empfohlen"
            else
                echo "   🔴 Buffer bereits hoch - prüfen Sie System-Performance"
            fi
        elif [ "$total_current_xruns" -gt 5 ]; then
            # Moderate Empfehlungen bei einigen Xruns
            if [ "$bufsize" -le 128 ]; then
                safe_buffer=512
                if command -v bc &> /dev/null; then
                    safe_latency=$(echo "scale=1; $safe_buffer * 1000 / $samplerate" | bc -l 2>/dev/null || echo "~$(($safe_buffer * 1000 / $samplerate))")
                else
                    safe_latency="~$(($safe_buffer * 1000 / $samplerate))"
                fi
                echo "   🟡 Stabilität: $safe_buffer Samples = ${safe_latency}ms empfohlen"
            fi
        else
            # Standard-Empfehlungen bei wenigen/keinen Xruns
            if [ "$bufsize" -le 64 ]; then
                next_buffer=128
                if command -v bc &> /dev/null; then
                    next_latency=$(echo "scale=1; $next_buffer * 1000 / $samplerate" | bc -l 2>/dev/null || echo "~$(($next_buffer * 1000 / $samplerate))")
                else
                    next_latency="~$(($next_buffer * 1000 / $samplerate))"
                fi
                echo "   🟡 Stabiler: $next_buffer Samples = ${next_latency}ms"
            elif [ "$bufsize" -le 128 ]; then
                safe_buffer=256
                if command -v bc &> /dev/null; then
                    safe_latency=$(echo "scale=1; $safe_buffer * 1000 / $samplerate" | bc -l 2>/dev/null || echo "~$(($safe_buffer * 1000 / $samplerate))")
                else
                    safe_latency="~$(($safe_buffer * 1000 / $samplerate))"
                fi
                echo "   🟢 Stabiler: $safe_buffer Samples = ${safe_latency}ms"
            else
                echo "   ✅ Buffer bereits in stabilem Bereich"
            fi
        fi

        # Samplerate-Alternativen wenn nötig
        if [ "$samplerate" -gt 48000 ] && [ "$total_current_xruns" -gt 10 ]; then
            if command -v bc &> /dev/null; then
                alt_latency=$(echo "scale=1; $bufsize * 1000 / 48000" | bc -l 2>/dev/null || echo "~$(($bufsize * 1000 / 48000))")
            else
                alt_latency="~$(($bufsize * 1000 / 48000))"
            fi
            echo "   🔄 Alternative: $bufsize@48kHz = ${alt_latency}ms (stabiler)"
        fi

        # Periods-Empfehlung bei Problemen
        if [ "$nperiods" != "unknown" ] && [ "$nperiods" -eq 2 ] && [ "$total_current_xruns" -gt 5 ]; then
            echo "   🔧 Wichtig: 3 periods statt $nperiods für bessere Latenz-Toleranz"
        fi
    else
        echo "   🟢 Stabil (256): Sehr stabil, niedrige Latenz (~5.3ms @ 48kHz)"
        echo "   🟡 Optimal (128): Gute Latenz, moderate CPU-Last (~2.7ms @ 48kHz)"
        echo "   🟠 Aggressiv (64): Niedrige Latenz, hohe CPU-Last (~1.3ms @ 48kHz)"
        echo "   🔴 Extrem (32): Nur für Tests (~0.7ms @ 48kHz)"
    fi
    echo ""
    echo "🎯 v4 Hybrid: Stabilität durch optimierte CPU-Zuweisung, Performance wo nötig!"
}

# Hauptfunktion
main_monitoring_loop() {
    log_message "🚀 MOTU M4 Dynamic Optimizer v4 gestartet"
    log_message "🏗️  Hybrid-Strategie: P-Cores Performance, Background E-Cores Powersave, IRQ E-Cores Performance"
    log_message "📊 System: Ubuntu 24.04, $(nproc) CPU-Kerne"
    log_message "🎯 Process-Pinning:"
    log_message "   P-Cores DAW/Plugins: $DAW_CPUS"
    log_message "   P-Cores JACK/PipeWire: $AUDIO_MAIN_CPUS"
    log_message "   E-Cores IRQ-Handling: $IRQ_CPUS"
    log_message "   E-Cores Background: $BACKGROUND_CPUS"
    log_message "🎵 Xrun-Monitoring: Aktiviert"

    # Script-Performance optimieren
    optimize_script_performance

    # Initiale CPU-Isolation-Prüfung
    check_cpu_isolation

    current_state="unknown"
    check_counter=0
    xrun_check_counter=0
    xrun_warning_threshold=10
    last_xrun_count=0

    while true; do
        motu_connected=$(check_motu_m4)

        if [ "$motu_connected" = "true" ]; then
            if [ "$current_state" != "optimized" ]; then
                activate_audio_optimizations
                current_state="optimized"
                check_counter=0
            else
                # Prozess-Affinität nur alle 30 Sekunden prüfen (Performance-Optimierung)
                check_counter=$((check_counter + 1))
                if [ $check_counter -ge 6 ]; then
                    optimize_audio_process_affinity
                    check_counter=0
                fi
            fi

            # Xrun-Monitoring alle 10 Sekunden (2 Zyklen)
            xrun_check_counter=$((xrun_check_counter + 1))
            if [ $xrun_check_counter -ge 2 ]; then
                # Prüfe Xruns der letzten 30 Sekunden
                if command -v journalctl &> /dev/null; then
                    current_xruns=$(journalctl --since "30 seconds ago" --no-pager -q 2>/dev/null | grep -i "mod\.jack-tunnel.*xrun" | wc -l || echo "0")

                    if [ "$current_xruns" -gt "$xrun_warning_threshold" ]; then
                        log_message "⚠️ Xrun-Warnung: $current_xruns Xruns in 30s (Grenze: $xrun_warning_threshold)"
                        log_message "💡 Empfehlung: Buffer-Größe erhöhen oder CPU-Last reduzieren"
                    elif [ "$current_xruns" -gt 0 ] && [ "$current_xruns" -ne "$last_xrun_count" ]; then
                        log_message "🎵 Xrun-Monitor: $current_xruns Xruns in letzten 30s"
                    fi

                    last_xrun_count=$current_xruns
                fi
                xrun_check_counter=0
            fi
        else
            if [ "$current_state" != "standard" ]; then
                deactivate_audio_optimizations
                current_state="standard"
            fi
        fi

        sleep 5
    done
}

# Live Xrun-Monitoring mit verbesserter PipeWire-JACK-Tunnel Erkennung
live_xrun_monitoring() {
    echo "=== MOTU M4 Live Xrun-Monitor ==="
    echo "⚡ Überwacht JACK/PipeWire Xruns in Echtzeit"
    echo "📊 Session gestartet: $(date '+%H:%M:%S')"

    # Zeige aktuelle JACK-Settings zu Beginn der Session
    jack_info=$(get_jack_settings)
    jack_status=$(echo "$jack_info" | cut -d'|' -f1)
    bufsize=$(echo "$jack_info" | cut -d'|' -f2)
    samplerate=$(echo "$jack_info" | cut -d'|' -f3)
    nperiods=$(echo "$jack_info" | cut -d'|' -f4)

    echo "🎵 JACK Status: $jack_status"
    if [ "$jack_status" = "✅ Aktiv" ]; then
        settings_text="${bufsize}@${samplerate}Hz"
        if [ "$nperiods" != "unknown" ]; then
            settings_text="$settings_text, $nperiods periods"
        fi
        if command -v bc &> /dev/null; then
            latency_ms=$(echo "scale=1; $bufsize * 1000 / $samplerate" | bc -l 2>/dev/null || echo "~$(($bufsize * 1000 / $samplerate))")
        else
            latency_ms="~$(($bufsize * 1000 / $samplerate))"
        fi
        echo "   Settings: $settings_text (${latency_ms}ms Latenz)"

        # Warnung bei aggressiven Settings
        if [ "$bufsize" -le 64 ]; then
            echo "   ⚠️ Sehr aggressive Buffer-Größe - Xruns wahrscheinlich"
        elif [ "$bufsize" -le 128 ]; then
            echo "   🟡 Moderate Buffer-Größe - Bei Xruns auf 256+ erhöhen"
        fi
    fi
    echo "🛑 Drücken Sie Ctrl+C zum Beenden"
    echo ""

    # Initialer Xrun-Zähler vom aktuellen Log-Stand
    initial_xruns=0
    if command -v journalctl &> /dev/null; then
        initial_xruns=$(journalctl --since "1 minute ago" --no-pager -q 2>/dev/null | grep -i "mod\.jack-tunnel.*xrun" | wc -l || echo "0")
    fi

    xrun_total=0
    xrun_session_start=$(date +%s)
    max_xruns_per_interval=0
    last_log_line=""

    # Xrun-Rate-Tracking für letzte 30 Sekunden
    xrun_timestamps=()

    while true; do
        # Aktuelle Xruns aus Logs seit Session-Start
        current_total_xruns=0
        new_xruns_this_interval=0

        if command -v journalctl &> /dev/null; then
            # Alle Xruns seit Session-Start
            session_start_time=$(date -d "@$xrun_session_start" '+%Y-%m-%d %H:%M:%S')
            current_total_xruns=$(journalctl --since "$session_start_time" --no-pager -q 2>/dev/null | grep -i "mod\.jack-tunnel.*xrun" | wc -l || echo "0")

            # Neue Xruns der letzten 5 Sekunden
            new_xruns_this_interval=$(journalctl --since "5 seconds ago" --no-pager -q 2>/dev/null | grep -i "mod\.jack-tunnel.*xrun" | wc -l || echo "0")
        fi

        # Session-Xruns berechnen (minus initiale)
        xrun_total=$((current_total_xruns - initial_xruns))
        if [ "$xrun_total" -lt 0 ]; then
            xrun_total=0
        fi

        # Tracking für neue Xruns
        current_timestamp=$(date +%s)
        if [ "$new_xruns_this_interval" -gt 0 ]; then
            xrun_timestamps+=($current_timestamp)
        fi

        # Entferne alte Timestamps (älter als 30 Sekunden)
        cutoff_time=$((current_timestamp - 30))
        new_timestamps=()
        for ts in "${xrun_timestamps[@]}"; do
            if [ "$ts" -gt "$cutoff_time" ]; then
                new_timestamps+=($ts)
            fi
        done
        xrun_timestamps=("${new_timestamps[@]}")

        # Xrun-Rate in letzten 30 Sekunden
        xrun_rate_30s=${#xrun_timestamps[@]}

        # Max Xruns pro Intervall tracking
        if [ "$new_xruns_this_interval" -gt "$max_xruns_per_interval" ]; then
            max_xruns_per_interval=$new_xruns_this_interval
        fi

        # Audio-Prozess-Info
        audio_processes=$(ps -eo pid,comm --no-headers | grep -E "jackd|pipewire|yoshimi|pianoteq|qjackctl" | wc -l)

        # MOTU M4 Status
        motu_status="❌ Nicht erkannt"
        if [ "$(check_motu_m4)" = "true" ]; then
            motu_status="✅ Verbunden"
        fi

        # Session-Zeit
        session_duration=$((current_timestamp - xrun_session_start))
        session_minutes=$((session_duration / 60))
        session_seconds=$((session_duration % 60))

        # Status-Icon basierend auf aktuellen Xruns
        status_icon="✅"
        if [ "$new_xruns_this_interval" -gt 0 ]; then
            status_icon="⚠️"
        fi
        if [ "$new_xruns_this_interval" -gt 2 ]; then
            status_icon="❌"
        fi

        # Live-Anzeige mit JACK-Settings (kompakt)
        current_display_time=$(date '+%H:%M:%S')

        # Kompakte JACK-Info für Live-Display
        jack_compact=""
        current_jack_info=$(get_jack_settings)
        current_jack_status=$(echo "$current_jack_info" | cut -d'|' -f1)
        if [ "$current_jack_status" = "✅ Aktiv" ]; then
            current_bufsize=$(echo "$current_jack_info" | cut -d'|' -f2)
            current_samplerate=$(echo "$current_jack_info" | cut -d'|' -f3)
            jack_compact=" | 🎵 ${current_bufsize}@${current_samplerate}Hz"
        else
            jack_compact=" | 🎵 Inaktiv"
        fi

        printf "\r[%s] %s MOTU M4: %s | 🎯 Audio: %d%s | ⚠️ Session: %d | 🔥 30s: %d | 📈 Max: %d | ⏱️ %02d:%02d" \
               "$current_display_time" "$status_icon" "$motu_status" "$audio_processes" "$jack_compact" "$xrun_total" "$xrun_rate_30s" "$max_xruns_per_interval" "$session_minutes" "$session_seconds"

        # Bei neuen Xruns: Neue Zeile mit Details und Empfehlungen
        if [ "$new_xruns_this_interval" -gt 0 ]; then
            echo ""
            # Zeige die neueste Xrun-Meldung
            latest_xrun=$(journalctl --since "5 seconds ago" --no-pager -q 2>/dev/null | grep -i "mod\.jack-tunnel.*xrun" | tail -1)
            echo "🚨 [$current_display_time] Neue Xruns: $new_xruns_this_interval"
            if [ -n "$latest_xrun" ]; then
                xrun_details=$(echo "$latest_xrun" | cut -d' ' -f5-)
                echo "📋 Details: $xrun_details"
            fi

            # Dynamische Empfehlung bei Xruns
            if [ "$current_jack_status" = "✅ Aktiv" ]; then
                current_bufsize=$(echo "$current_jack_info" | cut -d'|' -f2)
                current_samplerate=$(echo "$current_jack_info" | cut -d'|' -f3)
                current_nperiods=$(echo "$current_jack_info" | cut -d'|' -f4)

                if [ "$current_bufsize" != "unknown" ]; then
                    if [ "$current_bufsize" -le 64 ]; then
                        echo "💡 Empfehlung: Buffer von $current_bufsize auf 128+ Samples erhöhen"
                    elif [ "$current_bufsize" -le 128 ] && [ "$xrun_rate_30s" -gt 5 ]; then
                        echo "💡 Empfehlung: Buffer von $current_bufsize auf 256 Samples erhöhen"
                    elif [ "$current_nperiods" != "unknown" ] && [ "$current_nperiods" -eq 2 ] && [ "$xrun_rate_30s" -gt 3 ]; then
                        echo "💡 Tipp: 3 periods statt $current_nperiods für bessere Latenz-Toleranz"
                    fi
                fi
            fi
        fi

        sleep 2
    done
}

# Hauptmenü
case "${1:-monitor}" in
    "monitor"|"daemon")
        main_monitoring_loop
        ;;
    "live-xruns"|"xrun-monitor")
        live_xrun_monitoring
        ;;
    "once"|"run")
        motu_connected=$(check_motu_m4)
        if [ "$motu_connected" = "true" ]; then
            log_message "🎵 Einmalige Aktivierung der Hybrid Audio-Optimierungen"
            activate_audio_optimizations
        else
            log_message "🔧 MOTU M4 nicht erkannt - Deaktiviere Optimierungen"
            deactivate_audio_optimizations
        fi
        ;;
    "once-delayed")
        motu_connected=$(check_motu_m4)
        if [ "$motu_connected" = "true" ]; then
            log_message "🎵 Delayed System-Service: Warte auf User-Session Audio-Prozesse"

            # Intelligente Wartezeit für User-Audio-Services
            AUDIO_WAIT=0
            MAX_AUDIO_WAIT=45
            FOUND_USER_AUDIO=false

            while [ $AUDIO_WAIT -lt $MAX_AUDIO_WAIT ]; do
                # Prüfe auf User-Audio-Prozesse (nicht nur System-Audio)
                USER_PIPEWIRE=$(pgrep -f "pipewire" | wc -l)
                USER_JACK=$(pgrep -f "jackdbus" | wc -l)

                if [ "$USER_PIPEWIRE" -ge 2 ] || [ "$USER_JACK" -ge 1 ]; then
                    log_message "🎯 User-Audio-Services erkannt nach ${AUDIO_WAIT}s (PipeWire: $USER_PIPEWIRE, JACK: $USER_JACK)"
                    FOUND_USER_AUDIO=true
                    break
                fi

                sleep 2
                AUDIO_WAIT=$((AUDIO_WAIT + 2))

                # Fortschritts-Log alle 10 Sekunden
                if [ $((AUDIO_WAIT % 10)) -eq 0 ]; then
                    log_message "⏳ Warte auf User-Audio-Services... ${AUDIO_WAIT}/${MAX_AUDIO_WAIT}s (PipeWire: $USER_PIPEWIRE, JACK: $USER_JACK)"
                fi
            done

            if [ "$FOUND_USER_AUDIO" = "true" ]; then
                # Zusätzliche 3 Sekunden für Service-Initialisierung
                sleep 3
                log_message "🎵 Starte verzögerte Audio-Optimierung für User-Session-Prozesse"
                activate_audio_optimizations
            else
                log_message "⚠️  Timeout: Keine User-Audio-Services nach ${MAX_AUDIO_WAIT}s erkannt, starte Standard-Optimierung"
                activate_audio_optimizations
            fi
        else
            log_message "🔧 MOTU M4 nicht erkannt - Deaktiviere Optimierungen"
            deactivate_audio_optimizations
        fi
        ;;
    "status")
        show_status
        ;;
    "detailed"|"detail"|"monitor-detail")
        show_detailed_status
        ;;
    "stop"|"reset")
        log_message "🛑 Manueller Reset angefordert"
        deactivate_audio_optimizations
        ;;
    *)
        echo "MOTU M4 Dynamic Optimizer v4 - Hybrid-Strategie (Stabilität-optimiert)"
        echo ""
        echo "Verwendung: $0 [monitor|once|status|detailed|live-xruns|stop]"
        echo ""
        echo "Kommandos:"
        echo "  monitor     - Kontinuierliche Überwachung (Standard)"
        echo "  once        - Einmalige Optimierung"
        echo "  status      - Standard Status-Anzeige"
        echo "  detailed    - Detailliertes Hardware-Monitoring"
        echo "  live-xruns  - Live Xrun-Monitoring (Echtzeit)"
        echo "  stop        - Optimierungen deaktivieren"
        echo ""
        echo "CPU-Strategie v4 (Hybrid für Stabilität):"
        echo "  P-Cores 0-7:        Performance (Audio-Processing)"
        echo "  E-Cores 8-13:       Powersave (Background, weniger Störungen)"
        echo "  E-Cores 14-19:      Performance (IRQ-Handling)"
        echo ""
        echo "Process-Pinning bleibt optimal:"
        echo "  P-Cores 0-5: DAW/Plugins (maximale Single-Thread-Performance)"
        echo "  P-Cores 6-7: JACK/PipeWire (dedizierte Audio-Engine)"
        echo "  E-Cores 8-13: Background-Tasks"
        echo "  E-Cores 14-19: IRQ-Handling (stabile Latenz)"
        echo ""
        echo "🎯 v4 Vorteil: Optimale Balance aus Performance und Stabilität!"
        exit 1
        ;;
esac
