#!/usr/bin/env python3
"""Gera os textos do app (Localizable.strings) a partir dos textos do app Android.

Uso: python3 tools/textos-do-android.py <pasta res do app Android> <pasta App/Resources>

Só entram as chaves da lista CHAVES (as telas que este app já tem). Os quatro idiomas do
Android viram: values -> en, values-pt -> pt-BR, values-pt-rPT -> pt-PT, values-es -> es.
Texto que um idioma não traduz (marcado no Android como não traduzível) vem do inglês.
Os textos que só este app tem ficam na tabela EXTRAS, já nos quatro idiomas.
Os textos que o sistema mostra em nome do app (tabela SISTEMA) vão para InfoPlist.strings.
"""
import pathlib
import re
import sys
import xml.etree.ElementTree as ET

IDIOMAS = {"values": "en", "values-pt": "pt-BR", "values-pt-rPT": "pt-PT", "values-es": "es"}

CHAVES = """
app_name back site version_short language_tag home_date home_account
device_id_label device_key_label device_new_key device_unlink
playlists_reload playlists_reloading playlists_loading playlists_inactive playlists_blocked playlists_empty
playlists_active_until playlists_date_pattern playlists_offline playlists_offline_saved
playlists_register_refused playlists_too_many playlists_rejected
home_expires_month home_expires_week home_expires_day home_expired
account_device account_status account_last_check
cancel close
code_row code_row_description code_title code_hint code_field code_activate code_sending code_incomplete
code_invalid code_unavailable code_used code_already_active code_managed code_no_credits code_offline
code_too_many code_activated code_activated_days
new_key_title new_key_text new_key_confirm
unlink_title unlink_text unlink_not_linked unlink_confirm unlink_sending unlink_done
unlink_was_not_linked unlink_unavailable
home_media
media_pick_file media_pick_file_description media_open_link media_open_link_description
media_demo media_demo_description media_demo_title media_demo_credit
media_recents media_recents_clear media_recent_file media_recent_link media_recent_progress media_untitled
link_field_label link_hint link_paste link_clear link_open link_invalid
player_error_network player_error_http player_error_not_found player_error_format player_error_generic
player_error_code player_retry
""".split()

# Textos que só este app tem (o app Android ainda não tem a função). Quando o Android ganhar o
# mesmo texto, a chave sai daqui e entra em CHAVES.
EXTRAS = {
    # No lugar de "Ativo até" e a data, quando a ativação é de uma parceria (campo `sponsored` da
    # API). O texto tem de ser o mesmo em todos os apps.
    "playlists_active_partner": {
        "en": "Active via partner",
        "pt-BR": "Ativo por parceiro",
        "pt-PT": "Ativo por parceiro",
        "es": "Activo por socio",
    },
    # Botão de copiar ao lado do ID e da chave (pedido do dono em 12/11/2026).
    "device_copy_id": {"en": "Copy ID", "pt-BR": "Copiar o ID", "pt-PT": "Copiar o ID", "es": "Copiar el ID"},
    "device_copy_key": {"en": "Copy key", "pt-BR": "Copiar a chave", "pt-PT": "Copiar a chave", "es": "Copiar la clave"},
    "device_id_copied": {"en": "ID copied", "pt-BR": "ID copiado", "pt-PT": "ID copiado", "es": "ID copiado"},
    "device_key_copied": {"en": "Key copied", "pt-BR": "Chave copiada", "pt-PT": "Chave copiada", "es": "Clave copiada"},
    # A chave nova não pôde ser guardada no cofre do aparelho (o mesmo aviso do app de Windows).
    "new_key_failed": {
        "en": "The new key could not be saved. The key is still the same.",
        "pt-BR": "Não foi possível guardar a chave nova. A chave continua a mesma.",
        "pt-PT": "Não foi possível guardar a chave nova. A chave continua a mesma.",
        "es": "No se pudo guardar la clave nueva. La clave sigue siendo la misma.",
    },
    # Os controles do reprodutor. No Android eles vêm prontos da biblioteca de vídeo (com os textos
    # dela); aqui os controles são do app.
    "player_play": {"en": "Play", "pt-BR": "Reproduzir", "pt-PT": "Reproduzir", "es": "Reproducir"},
    "player_pause": {"en": "Pause", "pt-BR": "Pausar", "pt-PT": "Pausar", "es": "Pausar"},
    "player_replay": {"en": "Play again", "pt-BR": "Ver de novo", "pt-PT": "Ver de novo", "es": "Ver de nuevo"},
    "player_rewind": {
        "en": "Back 10 seconds",
        "pt-BR": "Voltar 10 segundos",
        "pt-PT": "Recuar 10 segundos",
        "es": "Retroceder 10 segundos",
    },
    "player_forward": {
        "en": "Forward 10 seconds",
        "pt-BR": "Avançar 10 segundos",
        "pt-PT": "Avançar 10 segundos",
        "es": "Avanzar 10 segundos",
    },
    "player_position": {"en": "Video position", "pt-BR": "Ponto do vídeo", "pt-PT": "Ponto do vídeo", "es": "Punto del video"},
    "player_subtitles": {"en": "Subtitles", "pt-BR": "Legendas", "pt-PT": "Legendas", "es": "Subtítulos"},
    "player_subtitles_off": {"en": "Off", "pt-BR": "Desligadas", "pt-PT": "Desligadas", "es": "Desactivados"},
    "player_settings": {"en": "Settings", "pt-BR": "Configurações", "pt-PT": "Definições", "es": "Configuración"},
    "player_speed": {"en": "Speed", "pt-BR": "Velocidade", "pt-PT": "Velocidade", "es": "Velocidad"},
    "player_speed_normal": {"en": "Normal", "pt-BR": "Normal", "pt-PT": "Normal", "es": "Normal"},
    "player_audio": {"en": "Audio", "pt-BR": "Áudio", "pt-PT": "Áudio", "es": "Audio"},
    "player_controls": {
        "en": "Show or hide the controls",
        "pt-BR": "Mostrar ou esconder os controles",
        "pt-PT": "Mostrar ou ocultar os controlos",
        "es": "Mostrar u ocultar los controles",
    },
    "player_loading": {
        "en": "Loading video",
        "pt-BR": "Carregando o vídeo",
        "pt-PT": "A carregar o vídeo",
        "es": "Cargando el video",
    },
}

# Textos que o sistema mostra em nome do app (arquivo InfoPlist.strings de cada idioma).
SISTEMA = {
    # A pergunta do iPhone quando o usuário abre o link de um vídeo que está na rede da casa dele.
    "NSLocalNetworkUsageDescription": {
        "en": "To open videos from addresses on your local network.",
        "pt-BR": "Para abrir vídeos de endereços da sua rede local.",
        "pt-PT": "Para abrir vídeos de endereços da sua rede local.",
        "es": "Para abrir videos de direcciones de tu red local.",
    },
}


def texto_do_android(valor: str) -> str:
    """Tira as marcas de escape do Android e troca %1$s por %1$@."""
    valor = valor.strip()
    if len(valor) >= 2 and valor[0] == '"' and valor[-1] == '"':
        valor = valor[1:-1]
    valor = valor.replace("\\'", "'").replace('\\"', '"').replace("\\n", "\n").replace("\\@", "@").replace("\\?", "?")
    valor = re.sub(r"%(\d+\$)?s", lambda m: "%" + (m.group(1) or "") + "@", valor)
    return valor


def ler(arquivo: pathlib.Path) -> dict:
    textos = {}
    for item in ET.parse(arquivo).getroot():
        nome = item.get("name")
        if item.tag == "string":
            textos[nome] = texto_do_android("".join(item.itertext()))
        elif item.tag == "plurals":
            for forma in item:
                quantidade = forma.get("quantity")
                if quantidade in ("one", "other"):
                    textos[f"{nome}.{quantidade}"] = texto_do_android("".join(forma.itertext()))
    return textos


def para_strings(valor: str) -> str:
    return valor.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def main() -> None:
    res, destino = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    ingles = ler(res / "values" / "strings.xml")
    for pasta, idioma in IDIOMAS.items():
        textos = ler(res / pasta / "strings.xml")
        linhas = ["/* Gerado por tools/textos-do-android.py a partir dos textos do app Android. Não editar à mão. */", ""]
        faltam = []
        for chave in CHAVES:
            nomes = [chave] if chave in ingles else [f"{chave}.one", f"{chave}.other"]
            for nome in nomes:
                valor = textos.get(nome, ingles.get(nome))
                if valor is None:
                    faltam.append(nome)
                    continue
                linhas.append(f'"{nome}" = "{para_strings(valor)}";')
        for chave, traducoes in EXTRAS.items():
            if chave in textos or chave in ingles:
                sys.exit(f"{chave}: o Android já tem este texto; tire-o de EXTRAS e ponha em CHAVES")
            linhas.append(f'"{chave}" = "{para_strings(traducoes[idioma])}";')
        if faltam:
            sys.exit(f"{idioma}: faltam os textos {faltam}")
        pasta_do_idioma = destino / f"{idioma}.lproj"
        pasta_do_idioma.mkdir(parents=True, exist_ok=True)
        (pasta_do_idioma / "Localizable.strings").write_text("\n".join(linhas) + "\n", encoding="utf-8")
        do_sistema = ["/* Gerado por tools/textos-do-android.py. Não editar à mão. */", ""]
        for chave, traducoes in SISTEMA.items():
            do_sistema.append(f'"{chave}" = "{para_strings(traducoes[idioma])}";')
        (pasta_do_idioma / "InfoPlist.strings").write_text("\n".join(do_sistema) + "\n", encoding="utf-8")
        print(f"{idioma}: {len(linhas) - 2} textos, {len(SISTEMA)} do sistema")


if __name__ == "__main__":
    main()
