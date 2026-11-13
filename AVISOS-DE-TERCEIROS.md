# Avisos de terceiros

## Material Design Icons (Google)

Os ícones do app (`App/Resources/Assets.xcassets/icon_*.imageset`) são os do Material Design Icons,
do Google, no estilo arredondado ("round"), tirados sem alteração do pacote
[`@material-design-icons/svg`](https://github.com/marella/material-design-icons), versão 0.14.15.

Licença: Apache License 2.0. O texto completo está em [`licencas/Apache-2.0.txt`](licencas/Apache-2.0.txt).

## MobileVLCKit (VideoLAN)

O motor de vídeo do app é o MobileVLCKit 3.7.5, do projeto VLC (VideoLAN). Ele não está neste
repositório: a compilação o baixa do endereço oficial do VLC, confere o arquivo
(`ci/motor-de-video.sh`) e o põe no app sem alteração, como uma biblioteca separada do código do
app.

Licença: GNU Lesser General Public License, versão 2.1 ou posterior. O texto completo está em
[`licencas/LGPL-2.1.txt`](licencas/LGPL-2.1.txt). O código-fonte dessa versão está em
<https://code.videolan.org/videolan/VLCKit> (ramo `3.0`, envio `a213fd11`).

## Big Buck Bunny (Blender Foundation)

O vídeo de demonstração (`App/Resources/demo_video.mp4`) é um trecho de 22 segundos de
"Big Buck Bunny", © 2008 Blender Foundation, <https://bigbuckbunny.org>, sob a licença Creative
Commons Atribuição 3.0 (CC BY 3.0), em tamanho e qualidade menores que o original. O crédito
aparece no app junto com o vídeo.
