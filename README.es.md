<p align="center">
  <img src="docs/assets/icon.png" width="128" height="128" alt="Icono de la app Cubby">
</p>

<h1 align="center">Cubby</h1>

<p align="center">
  <b>Todo lo que copias, a una pulsación de distancia.</b><br>
  Un gestor de portapapeles nativo para macOS, pensado para el teclado, que nunca sale de tu Mac.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="Licencia: MIT"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <b>Español</b> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a>
</p>

```sh
brew install --cask no1coder/tap/cubby
```

O descarga el DMG notarizado desde [Releases](https://github.com/no1coder/cubby/releases/latest). Requiere macOS 14 o posterior, con Apple silicon o Intel.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/panel-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/assets/screenshots/panel-light.png">
    <img src="docs/assets/screenshots/panel-light.png" width="380" alt="El panel de Cubby con tarjetas de texto, enlace, código, color, archivo e imagen">
  </picture>
</p>

Cubby vive en la barra de menús y recuerda lo que copias: texto, enlaces, código, colores, imágenes y archivos. Pulsa <kbd>⇧⌘V</kbd>, escribe unas letras y pulsa <kbd>↩</kbd> para pegar en la app que estabas usando, sin tocar el ratón. Está hecho para quienes copian y pegan todo el día (desarrolladores, diseñadores, redactores, cualquiera que maneje direcciones y fragmentos de texto) y quieren una herramienta rápida que respete su privacidad. Tu historial se queda en tu Mac; Cubby solo se conecta a internet para buscar una nueva versión (una vez al día, y puedes desactivarlo) o para traducir con un modelo de lenguaje que tú mismo configures.

**Lo más destacado**

- **Búsqueda y pegado al instante.** Tarjetas específicas para enlaces, código, colores y archivos, una búsqueda que también lee el texto de las imágenes, y pegado con <kbd>↩</kbd> o <kbd>⌘1</kbd>–<kbd>⌘9</kbd>.
- **Tu disposición.** Un panel flotante, una barra lateral acoplada al borde derecho o una bandeja de tarjetas en la parte inferior; además de una cuadrícula solo de imágenes con <kbd>⌃⇧V</kbd>.
- **Capturas de pantalla y anotaciones.** <kbd>⇧⌘2</kbd> captura una ventana o un área, te deja anotarla y la guarda en tu historial.
- **El tendedero.** Cuelga hasta 12 imágenes en la parte superior de la pantalla y bájalas desde la barra de menús cuando las necesites.
- **Protección de direcciones.** Recibe un aviso cuando un malware cambia una dirección de criptomonedas o un número de tarjeta que has copiado.
- **Traducción en macOS 26.** Traduce elementos del portapapeles y capturas de pantalla en su sitio, en el propio dispositivo o con tu propio modelo.

## Míralo en acción

<table>
  <tr>
    <td align="center" width="50%">
      <img src="docs/assets/gifs/search-paste.gif" alt="Abrir el panel de Cubby con Mayúsculas-Comando-V, escribir unas letras para filtrar el historial y pulsar Retorno para pegar el resultado en otra app"><br>
      <sub><b>Buscar y pegar.</b> Escribe para encontrar, <kbd>↩</kbd> para pegar.</sub>
    </td>
    <td align="center" width="50%">
      <img src="docs/assets/gifs/clothesline.gif" alt="Arrastrar hacia abajo desde la barra de menús para desplegar un tendedero de imágenes, pasar el puntero por las fotos y hacer clic en una para anotarla"><br>
      <sub><b>Tendedero.</b> Arrastra hacia abajo desde la barra de menús para llegar a tus imágenes fijadas.</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <img src="docs/assets/gifs/screenshot-annotate.gif" alt="Hacer una captura con Mayúsculas-Comando-2, seleccionar un área, añadir un recuadro, texto y una flecha, y copiarla"><br>
      <sub><b>Captura y anotaciones.</b> Captura, anota, pega.</sub>
    </td>
    <td align="center" width="50%">
      <img src="docs/assets/gifs/address-guard.gif" alt="Una dirección de Ethereum copiada que se sustituye en el portapapeles, y el aviso de Cubby que compara ambas direcciones carácter a carácter con las diferencias en rojo"><br>
      <sub><b>Protección de direcciones.</b> Una dirección sustituida se detecta antes de que la pegues.</sub>
    </td>
  </tr>
</table>

## Funciones

**Captura y búsqueda**

- Registra texto (el texto enriquecido conserva su formato RTF / HTML), enlaces, colores HEX, imágenes y archivos. Si vuelves a copiar algo, sube de nuevo al principio. Los favoritos nunca caducan; todo lo demás se recorta al límite que elijas (de 50 a 2000 elementos, 500 por omisión).
- Las tarjetas se parecen a su contenido: los enlaces muestran el título de la página y la dirección completa, el código muestra su lenguaje con resaltado de sintaxis, los colores muestran sus valores HEX y rgb(), y las imágenes se ven enteras. Cada tarjeta indica la app de origen, la hora y su número de <kbd>⌘</kbd>, agrupadas en Hoy, Ayer y Anteriores.
- Empieza a escribir para buscar. Deben coincidir todas las palabras, las coincidencias se resaltan, las mejores aparecen primero y cada categoría muestra cuántos elementos coinciden. También se pueden buscar rutas de archivo, apps de origen, títulos de enlaces y el texto de las imágenes (reconocido en tu Mac).
- Filtra por Texto, Enlaces, Imágenes, Archivos, Colores o Favoritos con <kbd>⇥</kbd>. <kbd>Espacio</kbd> abre una vista previa lateral; <kbd>⌘B</kbd> (**Pick Words**, elegir palabras) divide un texto en fichas de palabras para que pegues solo la parte que necesitas.
- Cinco posiciones del panel: junto al puntero, bajo el icono de la barra de menús, centrado, acoplado al borde derecho como barra lateral de altura completa o acoplado abajo como bandeja de tarjetas. <kbd>⌃⇧V</kbd> abre solo tus imágenes en una cuadrícula. Aspecto Claro, Oscuro o igual que el sistema; Liquid Glass en macOS 26.

**Pegar**

- <kbd>↩</kbd> pega en la app que estabas usando (el pie del panel indica cuál), <kbd>⇧↩</kbd> pega en el otro formato (original ↔ texto sin formato) y <kbd>⌘↩</kbd> solo copia.
- <kbd>⌘1</kbd> – <kbd>⌘9</kbd> pegan uno de los nueve primeros elementos; cualquier tarjeta se puede arrastrar a otra app.
- Pasa el puntero sobre una tarjeta para marcarla como favorita, previsualizarla, eliminarla o fijarla. <kbd>⌘⌫</kbd> la elimina y <kbd>⌘Z</kbd> la recupera.

**Capturas de pantalla**

- <kbd>⇧⌘2</kbd> congela la pantalla: pasa el puntero para elegir una ventana (<kbd>⇥</kbd> o el desplazamiento recorren las que se superponen), arrastra para marcar un área o pulsa <kbd>Espacio</kbd> para capturar limpiamente una sola ventana con su sombra.
- Anota con rectángulos, elipses, flechas, lápiz, marcador, mosaico, texto y pasos numerados; todo sigue siendo editable hasta que terminas.
- El resultado se copia **y se guarda en tu historial**. También puedes fijarlo en la pantalla, guardarlo como PNG o extraer su texto con OCR en el propio dispositivo. Una lupa copia el color bajo el puntero con <kbd>C</kbd>.

**Tendedero**

- Pulsa <kbd>⌘L</kbd> sobre una imagen para colgarla en un cordel en la parte superior de la pantalla (hasta 12). Arrastra hacia abajo desde un hueco vacío de la barra de menús, deja el puntero en el borde superior, pulsa <kbd>⌃⌥T</kbd> o usa el menú para desplegarlo.
- Haz doble clic en una foto para copiarla, arrástrala a una app o haz clic para ampliarla y anotarla; **Done & Hang Back** (terminar y volver a colgar) guarda el resultado como un elemento nuevo y conserva el original. Las fotos del tendedero no se eliminan al recortar el historial.

**Protección de direcciones**

- Si una dirección de Bitcoin, Ethereum / EVM, TRON, Solana o Litecoin, o un número de tarjeta bancaria, que has copiado se sustituye en el portapapeles a los pocos segundos mientras la misma app sigue en primer plano, un aviso compara ambos valores carácter a carácter con las diferencias en rojo. **Restore What I Copied** (restaurar lo que copié) vuelve a poner el tuyo.
- El elemento que lo sustituyó se marca en rojo en tu historial y no se puede pegar, copiar ni arrastrar. Cuando pegas una dirección desde Cubby, primero comprueba que el portapapeles sigue coincidiendo.
- Nunca vacía tu portapapeles ni intercepta <kbd>⌘V</kbd>. Se configura en Settings › Security (Ajustes › Seguridad).

**Traducción** (macOS 26)

- <kbd>⌘T</kbd> traduce el elemento seleccionado en una tarjeta junto al panel; <kbd>⌥↩</kbd> traduce y pega en un solo paso; mantén pulsada <kbd>⌥</kbd> para previsualizar una traducción en la lista.
- <kbd>⇧⌘T</kbd> en una captura de pantalla traduce su texto en su sitio, bloque a bloque.
- Usa por omisión la traducción de Apple en el propio dispositivo, o cualquier modelo compatible con OpenAI que configures (DeepSeek, Qwen, Kimi, Zhipu GLM, OpenAI, OpenRouter, un Ollama local o una URL personalizada). Consulta [Traducción](#traducción).

**Privacidad y acabado**

- Solo local, excluido de Time Machine, sin analíticas ni telemetría. Ignora el contenido de los gestores de contraseñas, las apps que excluyas y el texto que parezca una clave de API, una clave privada o un JWT. Pausa el registro cuando quieras. Consulta [Privacidad](#privacidad).
- Swift 6 con SwiftUI y AppKit, cero dependencias de terceros, binario Universal. Solo en la barra de menús, sin icono en el Dock. Interfaz en inglés y chino simplificado. Compatible con VoiceOver, Reducir movimiento y Aumentar contraste.
- Un pequeño punto azul en el icono de la barra de menús te avisa cuando hay una versión nueva.

## Diseño

La interfaz de la v0.3 se diseñó como un conjunto de maquetas antes de construirla. Aquí se muestran con la interfaz en chino, y algunos detalles cambiaron durante la implementación; la [guía de usuario](docs/USER-GUIDE.md) describe la app tal como se publica. Todas las maquetas están en [docs/design/ui-upgrade](docs/design/ui-upgrade).

<table>
  <tr>
    <td align="center" width="33%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/MainLight.png">
        <img src="docs/design/ui-upgrade/Main.png" width="280" alt="Maqueta del panel flotante: campo de búsqueda, barra de categorías, tarjetas específicas para una nota, un enlace de GitHub, código Swift, un color y una imagen, con un menú contextual">
      </picture><br>
      <sub>Panel flotante con tarjetas específicas</sub>
    </td>
    <td align="center" width="33%">
      <img src="docs/design/ui-upgrade/Search.png" width="280" alt="Maqueta de la búsqueda: coincidencias resaltadas con recuentos por categoría, un estado sin resultados que ofrece buscar solo la primera palabra y el estado de historial vacío"><br>
      <sub>Búsqueda, sin resultados y estados vacíos</sub>
    </td>
    <td align="center" width="33%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/ImageGridLight.png">
        <img src="docs/design/ui-upgrade/ImageGrid.png" width="280" alt="Maqueta de la vista Solo imágenes: una cuadrícula de dos columnas con capturas y fotos y una barra de herramientas al pasar el puntero">
      </picture><br>
      <sub>Solo imágenes (<kbd>⌃⇧V</kbd>)</sub>
    </td>
  </tr>
</table>

<table>
  <tr>
    <td align="center" width="50%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/DockRightLight.png">
        <img src="docs/design/ui-upgrade/DockRight.png" width="420" alt="Maqueta del panel acoplado al borde derecho como barra lateral de altura completa junto a una ventana de Notas">
      </picture><br>
      <sub>Acoplado al borde derecho</sub>
    </td>
    <td align="center" width="50%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/DockBottomLight.png">
        <img src="docs/design/ui-upgrade/DockBottom.png" width="420" alt="Maqueta del panel acoplado al borde inferior como bandeja de tarjetas, con la vista previa abierta sobre la tarjeta de imagen seleccionada">
      </picture><br>
      <sub>Acoplado al borde inferior</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/ClotheslineLight.png">
        <img src="docs/design/ui-upgrade/Clothesline.png" width="420" alt="Maqueta del tendedero: cuatro fotos sujetas con pinzas a un cordel en la parte superior de la pantalla, con la indicación clic para editar, doble clic para copiar, arrastrar a una app">
      </picture><br>
      <sub>El tendedero</sub>
    </td>
    <td align="center" width="50%">
      <img src="docs/design/ui-upgrade/ClotheslineEdit.png" width="420" alt="Maqueta de una foto del tendedero ampliada y anotada con un recuadro, una flecha, pasos numerados, texto y mosaico, con los botones Copiar y Terminar y volver a colgar"><br>
      <sub>Anotar una foto del tendedero</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <img src="docs/design/ui-upgrade/TamperAlert.png" width="420" alt="Maqueta del aviso de protección de direcciones: la dirección de Ethereum copiada y la que la sustituyó comparadas carácter a carácter, con las diferencias en rojo"><br>
      <sub>Aviso de protección de direcciones</sub>
    </td>
    <td align="center" width="50%">
      <img src="docs/design/ui-upgrade/Preview.png" width="420" alt="Maqueta de la vista previa lateral junto al panel: una nota de texto enriquecido mostrada completa con los botones Traducir, Pegar como texto sin formato y Pegar"><br>
      <sub>Vista previa lateral (Espacio)</sub>
    </td>
  </tr>
</table>

<table>
  <tr>
    <td align="center" width="33%">
      <img src="docs/design/ui-upgrade/Onboarding.png" width="280" alt="Maqueta del paso 3 de la guía de bienvenida: elegir un panel flotante, una barra lateral derecha o una bandeja inferior, y el aspecto"><br>
      <sub>Guía de bienvenida en cuatro pasos</sub>
    </td>
    <td align="center" width="33%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/SettingsLight.png">
        <img src="docs/design/ui-upgrade/Settings.png" width="280" alt="Maqueta de los Ajustes con barra lateral, mostrando General: aspecto, atajos, cinco posiciones del panel y opciones del tendedero">
      </picture><br>
      <sub>Ajustes con barra lateral</sub>
    </td>
    <td align="center" width="33%">
      <img src="docs/design/ui-upgrade/MenuBar.png" width="280" alt="Maqueta del menú de la barra de menús: línea de estado, abrir portapapeles, solo imágenes, captura de pantalla, tendedero y el submenú Posición del panel"><br>
      <sub>Menú de la barra de menús</sub>
    </td>
  </tr>
</table>

## Instalación

### Homebrew (recomendado)

```sh
brew install --cask no1coder/tap/cubby
```

Actualiza con `brew upgrade --cask cubby`.

### Descarga

1. Descarga `Cubby-x.y.z.dmg` desde la [última versión](https://github.com/no1coder/cubby/releases/latest).
2. Ábrelo y arrastra **Cubby** a **Aplicaciones**.
3. Abre Cubby desde Aplicaciones (no desde la imagen de disco ni desde la carpeta Descargas).

Las versiones están firmadas con un Developer ID y notarizadas por Apple, así que macOS solo pide confirmación una vez. Cada versión incluye también un `.zip` y un `SHA256SUMS.txt`.

### Compilar desde el código fuente

```sh
git clone https://github.com/no1coder/cubby.git
cd cubby
make install    # builds a Universal release app, copies it to /Applications and launches it
```

Requiere Xcode 26. Consulta [CONTRIBUTING.md](CONTRIBUTING.md) para ver las opciones de firma: con la firma ad hoc predeterminada, macOS olvida los permisos de Accesibilidad y Grabación de pantalla después de cada recompilación.

## Guía de usuario

La [guía de usuario](docs/USER-GUIDE.md) recorre cada función paso a paso. En la app, elige **User Guide** (guía de usuario) en el menú del icono de la barra de menús (también está en Settings › About y al final de la ayuda de atajos del panel).

## Primer inicio y permisos

En el primer inicio, una guía de cuatro pasos (Welcome, Permissions, Choose a Style, Shortcut) solicita dos permisos, te deja elegir la disposición y el aspecto del panel y configura tus atajos. Puedes volver a abrirla cuando quieras con **Setup Guide…** en el menú contextual del icono de la barra de menús.

**Acceso al portapapeles en macOS 15.4 y posterior.** Haz clic en **Grant Access** (conceder acceso) en la guía (o en Settings › Privacy) y elige **Allow Paste** (permitir pegar). Si no pasa nada, copia algo primero y vuelve a hacer clic. El aviso no tiene la opción «permitir siempre», así que configura también Cubby como **Permitir** en Ajustes del Sistema › Privacidad y seguridad › Pegar desde otras apps (llamado Pegar antes de macOS 26); cuando macOS ya lo haya preguntado, el botón cambia a **Open System Settings** y te lleva allí.

| Permiso | Por qué lo necesita Cubby | Dónde concederlo |
| --- | --- | --- |
| **Acceso al portapapeles** (macOS 15.4 y posterior) | Para leer lo que copias. Sin él, macOS no deja de preguntar o no se registra nada. | Haz clic en **Grant Access** y elige **Allow Paste**; luego, en Ajustes del Sistema › Privacidad y seguridad › Pegar desde otras apps → configura Cubby como **Permitir** |
| **Accesibilidad** | Para pegar enviando <kbd>⌘V</kbd> a la app en primer plano. Sin él, elegir un elemento solo lo copia. | Ajustes del Sistema › Privacidad y seguridad › Accesibilidad → activa **Cubby** |
| **Grabación de pantalla** (solo para capturas) | Para capturar la pantalla cuando haces una captura. Nunca se usa al iniciar ni en segundo plano. Cubby lo pide la primera vez que haces una. | Ajustes del Sistema › Privacidad y seguridad › Grabación de pantalla y audio del sistema (Grabación de pantalla en macOS 14) → activa **Cubby** |
| **Monitorización de entrada** (opcional) | Ayuda a la protección de direcciones a distinguir tu propio <kbd>⌘C</kbd> / <kbd>⌘X</kbd> de una sustitución. Solo detecta esos dos atajos, nunca lo que escribes. | Settings › Security › **Grant Access**, o Ajustes del Sistema › Privacidad y seguridad › Monitorización de entrada |

Después de activar la Grabación de pantalla, puede que macOS te pida salir de Cubby y volver a abrirlo; el botón **Quit & Reopen Cubby** de la ventana de Grabación de pantalla de Cubby hace ambas cosas.

Haz clic en el icono de la barra de menús para abrir el panel. Haz clic derecho (o Control-clic) en él para ver su estado y las opciones Only Images, Take Screenshot, Show Clothesline, Panel Position, Appearance, Pause Recording, Clear History, User Guide, Setup Guide, Check for Updates, Settings y Quit.

## Atajos de teclado

| Tecla | Acción |
| --- | --- |
| <kbd>⇧⌘V</kbd> | Abrir o cerrar el panel (global, personalizable) |
| <kbd>⌃⇧V</kbd> | Abrir el panel solo con tus imágenes (global, personalizable o desactivable) |
| <kbd>⌃⌥T</kbd> | Mostrar u ocultar el tendedero (global, personalizable o desactivable) |
| <kbd>⇧⌘2</kbd> | Hacer una captura de pantalla (global, personalizable o desactivable) |
| Escribe cualquier cosa | Buscar |
| <kbd>↑</kbd> <kbd>↓</kbd> (<kbd>←</kbd> <kbd>→</kbd> en la cuadrícula de imágenes y la bandeja inferior) | Mover la selección |
| <kbd>↩</kbd> o doble clic | Pegar en la app actual |
| <kbd>⇧↩</kbd> / <kbd>⌘↩</kbd> | Pegar en el otro formato / solo copiar |
| <kbd>⌘1</kbd> – <kbd>⌘9</kbd> | Pegar el elemento 1 – 9 |
| <kbd>Espacio</kbd> / <kbd>⌘Y</kbd> | Mostrar u ocultar la vista previa (<kbd>Espacio</kbd> solo con el campo de búsqueda vacío) |
| <kbd>⇥</kbd> / <kbd>⇧⇥</kbd> | Categoría siguiente / anterior |
| <kbd>⌘B</kbd> | Pick Words (elegir palabras) |
| <kbd>⌘P</kbd> | Marcar / desmarcar como favorito |
| <kbd>⇧⌘P</kbd> | Fijar la imagen seleccionada en la pantalla |
| <kbd>⌘L</kbd> | Colgar la imagen seleccionada en el tendedero, o descolgarla |
| <kbd>⌘T</kbd> / <kbd>⌥↩</kbd> / mantener <kbd>⌥</kbd> | Traducir / traducir y pegar / previsualizar la traducción (macOS 26) |
| <kbd>⌘⌫</kbd> / <kbd>⌘Z</kbd> | Eliminar / deshacer la eliminación |
| <kbd>⌘O</kbd> | Abrir el enlace o el archivo |
| <kbd>⌘,</kbd> | Ajustes |
| <kbd>esc</kbd> | Retroceder: cerrar la ayuda o la vista previa → borrar la búsqueda → cerrar el panel |

<details>
<summary><b>Atajos de las capturas de pantalla</b></summary>
<br>

| Tecla | Acción |
| --- | --- |
| Clic / arrastrar | Seleccionar la ventana o pantalla resaltada / seleccionar un área |
| <kbd>⇥</kbd> / <kbd>⇧⇥</kbd> o desplazamiento | Recorrer las ventanas superpuestas bajo el puntero, hasta la pantalla completa |
| <kbd>Espacio</kbd> | Modo ventana: capturar solo la ventana resaltada, sin obstáculos y con su sombra (<kbd>⌥</kbd>-clic omite la sombra) |
| Mantener <kbd>⇧</kbd> / <kbd>⌥</kbd> / <kbd>Espacio</kbd> al arrastrar | Selección cuadrada / crecer desde el centro / mover la selección |
| <kbd>⌘A</kbd> | Seleccionar toda la pantalla |
| <kbd>↑</kbd> <kbd>↓</kbd> <kbd>←</kbd> <kbd>→</kbd> | Mover la selección o la anotación seleccionada 1 pt (10 pt con <kbd>⇧</kbd>) |
| <kbd>R</kbd> <kbd>O</kbd> <kbd>A</kbd> <kbd>P</kbd> <kbd>H</kbd> <kbd>M</kbd> <kbd>T</kbd> <kbd>N</kbd> | Rectángulo, elipse, flecha, lápiz, marcador, mosaico, texto, número (la misma tecla o <kbd>V</kbd> vuelve al puntero) |
| <kbd>⌫</kbd> | Eliminar la anotación seleccionada |
| <kbd>⌘Z</kbd> / <kbd>⇧⌘Z</kbd> | Deshacer / rehacer anotaciones |
| <kbd>C</kbd> | Copiar el color bajo la lupa (mantén <kbd>⇧</kbd> para RGB) |
| <kbd>↩</kbd>, <kbd>⌘C</kbd> o doble clic | Terminar: copiar al portapapeles y al historial |
| <kbd>⌘S</kbd> | Guardar como PNG |
| <kbd>⌘P</kbd> | Fijar en la pantalla |
| <kbd>⌘T</kbd> | Extraer el texto y copiarlo |
| <kbd>⇧⌘T</kbd> | Traducir el texto de la selección (macOS 26) |
| Clic derecho | Borrar la selección y volver a seleccionar; sin selección, cancelar |
| <kbd>esc</kbd> | Cancelar (pulsa dos veces si ya has dibujado algo) |

</details>

El botón del teclado en el pie del panel muestra la lista de atajos dentro de la app, y al hacer clic derecho en una tarjeta se listan sus acciones. La [guía de usuario](docs/USER-GUIDE.md#shortcut-reference) tiene la referencia completa, incluidos el tendedero, la tarjeta de traducción y las imágenes fijadas.

## Traducción

En macOS 26, selecciona un elemento en el panel y pulsa <kbd>⌘T</kbd>: se abre una tarjeta de traducción junto al panel que se va completando párrafo a párrafo, conservando títulos, listas, negritas y enlaces. En una captura de pantalla, <kbd>⇧⌘T</kbd> dibuja cada traducción donde estaba el texto original; mantén pulsada <kbd>Espacio</kbd> para echar un vistazo al original o arrastra el divisor para compararlos.

| Traducir una captura en su sitio | Traducir un elemento del portapapeles |
| :---: | :---: |
| <img src="docs/assets/screenshots/screenshot-translate-dark.png" alt="Una captura de dos ventanas en inglés en la que cada etiqueta y línea se sustituye en su sitio por su traducción al chino"> | <img src="docs/assets/screenshots/clipboard-translate-dark.png" alt="La tarjeta de traducción junto al panel, con un correo en inglés y su traducción al chino párrafo a párrafo"> |

Elige el motor en **Settings › Translation** (Ajustes › Traducción):

- **System Translation** (predeterminado): la traducción integrada de Apple, en tu Mac y sin conexión. macOS pregunta antes de descargar un paquete de idioma.
- **Large language model** (modelo de lenguaje grande): cualquier servicio de Chat Completions compatible con OpenAI. Hay ajustes predefinidos para DeepSeek, Qwen (Alibaba Cloud Model Studio), Kimi (Moonshot AI), Zhipu GLM (y Z.ai), OpenAI, OpenRouter y Ollama en tu Mac, o una URL base personalizada.

Tu clave de API se guarda en el llavero de inicio de sesión de macOS, nunca en las preferencias, el historial ni los registros. Con un modelo, solo se envía el texto que traduces (en una imagen o captura, el texto reconocido en ella); la imagen nunca se sube, el texto bajo un mosaico nunca se envía y el texto que parece un secreto solo se envía después de que lo confirmes (nunca desde una imagen). Los servicios remotos deben usar HTTPS; HTTP sin cifrar solo se permite para `localhost`.

## Privacidad

- **Solo local.** El historial está en `~/Library/Application Support/Cubby`: la carpeta solo la puedes leer tú (0700), los archivos son 0600 y está excluida de Time Machine.
- **Ignora el contenido sensible.** Los elementos marcados como ocultos o transitorios (como hacen los gestores de contraseñas), las apps de tu lista de apps ignoradas (Settings › Privacy) y, salvo que lo desactives, el texto que parece una clave de API, una clave privada o un JWT.
- **Pega donde esperas.** Antes de enviar <kbd>⌘V</kbd>, Cubby comprueba que la app de destino sigue en primer plano y que la dirección que va a pegar sigue siendo la de tu portapapeles.
- **La protección de direcciones es local.** Con la Monitorización de entrada solo detecta <kbd>⌘C</kbd> y <kbd>⌘X</kbd>, nunca lo que escribes, y su registro de seguridad se queda en tu Mac y solo contiene valores abreviados.
- **Las capturas y el texto de las imágenes se quedan en tu Mac.** La pantalla solo se captura cuando haces una captura, y si cancelas no queda nada. El texto de las imágenes se reconoce en tu Mac con el framework Vision de Apple y solo se guarda en tu archivo de historial.
- **Solo se conecta para las actualizaciones y el servicio de traducción que configures.** La búsqueda de actualizaciones (una vez al día, activada por omisión, se desactiva en Settings › General) solo lee el número de la última versión en `api.github.com/repos/no1coder/cubby/releases/latest` y no sube nada. Un modelo de lenguaje que configures solo recibe el texto que traduces.
- **Sin analíticas, sin telemetría, sin informes de fallos.**

Todos los detalles en [PRIVACY.md](PRIVACY.md).

## Preguntas frecuentes

<details>
<summary><b>La Accesibilidad está activada, pero Cubby solo copia en lugar de pegar.</b></summary>

macOS vincula el permiso a la firma de código de la app. Tras una actualización, o tras instalar una compilación firmada de otra forma (por ejemplo, una compilada desde el código fuente y luego una versión oficial), el interruptor puede seguir pareciendo activado aunque ya no tenga efecto. Abre Ajustes del Sistema › Privacidad y seguridad › Accesibilidad, selecciona **Cubby**, haz clic en **−** para quitarlo y vuelve a añadirlo, o reinicia Cubby y concede el acceso. También puedes ejecutar:

```sh
tccutil reset Accessibility io.github.no1coder.Cubby
```

Después abre Cubby y vuelve a conceder el acceso.

</details>

<details>
<summary><b>macOS dice que Cubby no se puede abrir o no se puede verificar.</b></summary>

Las versiones oficiales están notarizadas, así que solo deberías ver una confirmación de «descargado de internet» y nada más. Asegúrate de haber descargado Cubby desde la página de Releases de este repositorio o de haberlo instalado con Homebrew, y de abrirlo desde Aplicaciones. Puedes comprobar la firma con:

```sh
spctl -a -vvv /Applications/Cubby.app    # expect: source=Notarized Developer ID
```

Si la comprobación falla, elimina la app, vuelve a descargarla y [abre una incidencia](https://github.com/no1coder/cubby/issues/new/choose) si el problema persiste. No hace falta desactivar Gatekeeper.

</details>

<details>
<summary><b>Cubby me avisó de que se sustituyó una dirección. ¿Qué hago?</b></summary>

El portapapeles cambió a otra dirección o número de tarjeta del mismo tipo justo después de que copiaras uno, mientras la misma app seguía en primer plano. Compara los dos valores del aviso. Si no hiciste tú el cambio, haz clic en **Restore What I Copied** y revisa tu Mac en busca de software que no reconozcas; si lo hiciste tú (por ejemplo, copiaste rápidamente una segunda dirección en la misma app), haz clic en **I Changed It Myself** (lo cambié yo). Permitir la Monitorización de entrada en Settings › Security ayuda a Cubby a reconocer tus propias copias.

</details>

<details>
<summary><b>¿Dónde se guardan mis datos?</b></summary>

- Historial: `~/Library/Application Support/Cubby` (`history.json` más una carpeta `Images`)
- Preferencias: `~/Library/Preferences/io.github.no1coder.Cubby.plist`
- Capturas guardadas: donde elijas en el cuadro de diálogo de guardar o, con **Ask where to save each time** desactivado, en la carpeta indicada en Settings › Screenshots (por omisión, la misma carpeta que las capturas de macOS)

Settings › History puede mostrar la carpeta en el Finder. Consulta [PRIVACY.md](PRIVACY.md) para saber exactamente qué se guarda.

</details>

<details>
<summary><b>¿Puedo exportar o hacer una copia de seguridad de mi historial?</b></summary>

Todavía no; la importación y la exportación están en la [hoja de ruta](docs/ROADMAP.md). La carpeta de datos se excluye de Time Machine a propósito, porque el portapapeles suele contener información sensible. Hasta que llegue la exportación, puedes salir de Cubby y copiar `~/Library/Application Support/Cubby` a mano. Ten en cuenta que esa copia contiene todo lo que has copiado, sin cifrar.

</details>

<details>
<summary><b>¿Cómo desinstalo Cubby?</b></summary>

Con Homebrew, esto elimina la app y todos sus datos:

```sh
brew uninstall --zap --cask cubby
```

Si no, sal de Cubby y ejecuta:

```sh
rm -rf /Applications/Cubby.app ~/Library/Application\ Support/Cubby
defaults delete io.github.no1coder.Cubby
tccutil reset All io.github.no1coder.Cubby
```

</details>

## Contribuir

Los informes de errores, las traducciones y las pull requests son bienvenidos. [CONTRIBUTING.md](CONTRIBUTING.md) explica cómo compilar desde el código fuente, las pruebas, el estilo de código y la firma local. Lee el [Código de conducta](CODE_OF_CONDUCT.md) e informa de los problemas de seguridad de forma privada como se describe en [SECURITY.md](SECURITY.md).

## Hoja de ruta

La v0.3 trajo las disposiciones acopladas, la cuadrícula de imágenes, el tendedero, la protección de direcciones, Pick Words y un panel, unos ajustes y una guía de bienvenida rediseñados. Sigue previsto: limpieza automática por antigüedad, selección múltiple y pegado combinado, una cola de pegado, transformaciones de texto, edición antes de pegar, Vista rápida e importación / exportación; y, para las capturas, seleccionar elementos de la interfaz manteniendo pulsada <kbd>⌥</kbd> y restaurar la última selección. Consulta [docs/ROADMAP.md](docs/ROADMAP.md) para más detalles y [CHANGELOG.md](CHANGELOG.md) para las notas de versión.

## Licencia

[MIT](LICENSE) © 2026 no1coder
