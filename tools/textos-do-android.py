#!/usr/bin/env python3
"""Gera os textos do app (Localizable.strings) a partir dos textos do app Android.

Uso: python3 tools/textos-do-android.py <pasta res do app Android> <pasta App/Resources>

Só entram as chaves da lista CHAVES (as telas que este app já tem). Os quatro idiomas do
Android viram: values -> en, values-pt -> pt-BR, values-pt-rPT -> pt-PT, values-es -> es.
Texto que um idioma não traduz (marcado no Android como não traduzível) vem do inglês.
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
""".split()


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
        if faltam:
            sys.exit(f"{idioma}: faltam os textos {faltam}")
        pasta_do_idioma = destino / f"{idioma}.lproj"
        pasta_do_idioma.mkdir(parents=True, exist_ok=True)
        (pasta_do_idioma / "Localizable.strings").write_text("\n".join(linhas) + "\n", encoding="utf-8")
        print(f"{idioma}: {len(linhas) - 2} textos")


if __name__ == "__main__":
    main()
