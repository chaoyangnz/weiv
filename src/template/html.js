export const HTML_TAGS = [
  'a',
  'abbr',
  'acronym',
  'address',
  'applet',
  'area',
  'article',
  'aside',
  'audio',
  'b',
  'base',
  'basefont',
  'bdi',
  'bdo',
  'big',
  'blockquote',
  'body',
  'br',
  'button',
  'canvas',
  'caption',
  'center',
  'cite',
  'code',
  'col',
  'colgroup',
  'datalist',
  'dd',
  'del',
  'details',
  'dfn',
  'dialog',
  'dir',
  'div',
  'dl',
  'dt',
  'em',
  'embed',
  'fieldset',
  'figcaption',
  'figure',
  'font',
  'footer',
  'form',
  'frame',
  'frameset',
  'h1',
  'head',
  'header',
  'hr',
  'html',
  'i',
  'iframe',
  'img',
  'input',
  'ins',
  'kbd',
  'label',
  'legend',
  'li',
  'link',
  'main',
  'map',
  'mark',
  'menu',
  'menuitem',
  'meta',
  'meter',
  'nav',
  'noframes',
  'noscript',
  'object',
  'ol',
  'optgroup',
  'option',
  'output',
  'p',
  'param',
  'picture',
  'pre',
  'progress',
  'q',
  'rp',
  'rt',
  'ruby',
  's',
  'samp',
  'script',
  'section',
  'select',
  'small',
  'source',
  'span',
  'strike',
  'strong',
  'style',
  'sub',
  'summary',
  'sup',
  'table',
  'tbody',
  'td',
  'textarea',
  'tfoot',
  'th',
  'thead',
  'time',
  'title',
  'tr',
  'track',
  'tt',
  'u',
  'ul',
  'var',
  'video',
  'wbr'
]

export const HTML_EVENT_ATTRIBUTES = [
  'onblur',
  'onchange',
  'oncontextmenu',
  'onfocus',
  'oninput',
  'oninvalid',
  'onreset',
  'onsearch',
  'onselect',
  'onsubmit',
  'onkeydown',
  'onkeypress',
  'onkeyup',
  'onclick',
  'ondblclick',
  'onmousedown',
  'onmousemove',
  'onmouseout',
  'onmouseover',
  'onmouseup',
  'onwheel',
  'ondrag',
  'ondragend',
  'ondragenter',
  'ondragleave',
  'ondragover',
  'ondragstart',
  'ondrop',
  'onscroll',
  'oncopy',
  'oncut',
  'onpaste'
]

export const BOOLEAN_ATTRIBUTES = [
  ['checked', 'input', {type: 'checkbox'}],
  ['checked', 'input', {type: 'radio'}],
  ['selected', 'option'],
  ['disabled', 'input'],
  ['disabled', 'textarea'],
  ['disabled', 'button'],
  ['disabled', 'select'],
  ['disabled', 'option'],
  ['disabled', 'optgroup'],
  ['autofocus', 'input'],
  ['readonly', 'input', {type: 'text'}],
  ['readonly', 'input', {type: 'password'}],
  ['readonly', 'textarea'],
  ['multiple', 'select'],
  ['ismap', 'img'],
  ['ismap', 'input', {type: 'image'}],
  ['defer', 'script'],
  ['noresize', 'frame'],
  ['nowrap', 'td'],
  ['nowrap', 'th'],
  ['noshade', 'hr'],
  ['compact', 'ul'],
  ['compact', 'ol'],
  ['compact', 'dl'],
  ['compact', 'menu'],
  ['compact', 'dir']
]

export const HTML_GLOBAL_ATTRIBUTES = [
  'accesskey', //	Global attribute	Defines a keyboard shortcut to activate or add focus to the element.
  'class', //	Often used with CSS to style elements with common properties.
  'contextmenu', // Global attribute	Defines the ID of a menu, element which will serve as the element's context menu.
  'contenteditable', // Global attribute	Indicates whether the element's content is editable.
  'draggable', // Global attribute	Defines whether the element can be dragged.
  'dropzone', // Global attribute	Indicates that the element accept the dropping of content on it.
  'dir', // Global attribute	Defines the text direction. Allowed values are ltr (Left-To-Right) or rtl (Right-To-Left)
  'hidden', // Global attribute	Prevents rendering of given element, while keeping child elements, e.g. script elements, active.
  'id', // Global attribute	Often used with CSS to style a specific element. The value of this attribute must be unique.
  'itemprop', // Global attribute
  'lang', // Global attribute	Defines the language used in the element.
  'slot' // Global attribute	Assigns a slot in a shadow DOM shadow tree to an element.
]

export const HTML_TAG_ATTRIBUTES = {
  // List of types the server accepts, typically a file type.
  accept:	['form', 'input'],
  // List of supported charsets.
  'accept-charset':	['form'],
  // The URI of a program that processes the information submitted via the form.
  action: ['form'],
  // Specifies the horizontal alignment of the element.
  align:	['applet', 'caption', 'col', 'colgroup', 'hr', 'iframe', 'img', 'table', 'tbody', 'td', 'tfoot', 'th', 'thead', 'tr'],
  alt:	['applet', 'area', 'img', 'input'], //	Alternative text in case an image can't be displayed.
  async: ['script'], //	Indicates that the script should be executed asynchronously.
  autocomplete:	['form', 'input'], //	Indicates whether controls in this form can by default have their values automatically completed by the browser.
  autofocus: ['button', 'input', 'keygen', 'select', 'textarea'], //	The element should be automatically focused after the page loaded.
  autoplay:	['audio', 'video'], //	The audio or video should play as soon as possible.
  // Background color of the element. Note: This is a legacy attribute. Please use the CSS background-color property instead.
  bgcolor: ['body', 'col', 'colgroup', 'marquee', 'table', 'tbody', 'tfoot', 'td', 'th', 'tr'],
  border:	['img', 'object', 'table'], // The border width. Note: This is a legacy attribute. Please use the CSS border property instead.
  buffered:	['audio', 'video'], //	Contains the time range of already buffered media.
  challenge: ['keygen'], //	A challenge string that is submitted along with the public key.
  charset: ['meta', 'script'], //	Declares the character encoding of the page or script.
  checked: ['command', 'input'], // Indicates whether the element should be checked on page load.
  cite: ['blockquote', 'del', 'ins', 'q'], // Contains a URI which points to the source of the quote or change.

  code: ['applet'], // Specifies the URL of the applet's class file to be loaded and executed.
  codebase: ['applet'], // This attribute gives the absolute or relative URL of the directory where applets'], //.class files referenced by the code attribute are stored.
  // This attribute sets the text color using either a named color or a color specified in the hexadecimal #RRGGBB format. Note: This is a legacy attribute. Please use the CSS color property instead.
  color: ['basefont', 'font', 'hr'],
  cols: ['textarea'], // Defines the number of columns in a textarea.
  colspan: ['td', 'th'], // The colspan attribute defines the number of columns a cell should span.
  content: ['meta'], // A value associated with http-equiv or name depending on the context.
  controls: ['audio', 'video'], // Indicates whether the browser should show playback controls to the user.
  coords: ['area'], // A set of values specifying the coordinates of the hot-spot region.
  crossorigin: ['audio', 'img', 'link', 'script', 'video'], // How the element handles cross-origin requests
  data: ['object'], // Specifies the URL of the resource.
  // data-*	Global attribute	Lets you attach custom attributes to an HTML element.
  datetime: ['del', 'ins', 'time'], // Indicates the date and time associated with the element.
  default: ['track'], // Indicates that the track should be enabled unless the user's preferences indicate something different.
  defer: ['script'], // Indicates that the script should be executed after the page has been parsed.
  dirname: ['input', 'textarea'],
  disabled: ['button', 'command', 'fieldset', 'input', 'keygen', 'optgroup', 'option', 'select', 'textarea'], // Indicates whether the user can interact with the element.
  download: ['a', 'area'], // Indicates that the hyperlink is to be used for downloading a resource.
  enctype: ['form'], // Defines the content type of the form date when the method is POST.
  for: ['label', 'output'], // Describes elements which belongs to this one.
  form: ['button', 'fieldset', 'input', 'keygen', 'label', 'meter', 'object', 'output', 'progress', 'select', 'textarea'], // Indicates the form that is the owner of the element.
  formaction: ['input', 'button'], // Indicates the action of the element, overriding the action defined in the 'form'.
  headers: ['td', 'th'], // IDs of the 'th'], //elements which applies to this element.
  // Specifies the height of elements listed here. For all other elements, use the CSS height property.
  // Note: In some instances, such as 'div', this is a legacy attribute, in which case the CSS height property should be used instead.
  height: ['canvas', 'embed', 'iframe', 'img', 'input', 'object', 'video'],
  high: ['meter'], // Indicates the lower bound of the upper range.
  href: ['a', 'area', 'base', 'link'], // The URL of a linked resource.
  hreflang: ['a', 'area', 'link'], // Specifies the language of the linked resource.
  'http-equiv': ['meta'],
  icon: ['command'], // Specifies a picture which represents the command.
  integrity: ['link', 'script'], // Security Feature that allows browsers to verify what they fetch.
  ismap: ['img'], // Indicates that the image is part of a server-side image map.
  keytype: ['keygen'], // Specifies the type of key generated.
  kind: ['track'], // Specifies the kind of text track.
  label: ['track'], // Specifies a user-readable title of the text track.
  language: ['script'], // Defines the script language used in the element.
  list: ['input'], // Identifies a list of pre-defined options to suggest to the user.
  loop: ['audio', 'bgsound', 'marquee', 'video'], // Indicates whether the media should start playing from the start when it's finished.
  low: ['meter'], // Indicates the upper bound of the lower range.
  manifest: ['html'], // Specifies the URL of the document's cache manifest.
  max: ['input', 'meter', 'progress'], // Indicates the maximum value allowed.
  maxlength: ['input', 'textarea'], // Defines the maximum number of characters allowed in the element.
  minlength: ['input', 'textarea'], // Defines the minimum number of characters allowed in the element.
  media: ['a', 'area', 'link', 'source', 'style'], // Specifies a hint of the media for which the linked resource was designed.
  method: ['form'], // Defines which HTTP method to use when submitting the form. Can be GET (default) or POST.
  min: ['input', 'meter'], // Indicates the minimum value allowed.
  multiple: ['input', 'select'], // Indicates whether multiple values can be entered in an input of the type email or file.
  muted: ['audio', 'video'], // Indicates whether the audio will be initially silenced on page load.
  // Name of the element. For example used by the server to identify the fields in form submits.
  name: ['button', 'form', 'fieldset', 'iframe', 'input', 'keygen', 'object', 'output', 'select', 'textarea', 'map', 'meta', 'param'],
  novalidate: ['form'], // This attribute indicates that the form shouldn't be validated when submitted.
  open: ['details'], // Indicates whether the details will be shown on page load.
  optimum: ['meter'], // Indicates the optimal numeric value.
  pattern: ['input'], // Defines a regular expression which the element's value will be validated against.
  ping: ['a', 'area'],
  placeholder: ['input', 'textarea'], // Provides a hint to the user of what can be entered in the field.
  poster: ['video'], // A URL indicating a poster frame to show until the user plays or seeks.
  preload: ['audio', 'video'], // Indicates whether the whole resource, parts of it or nothing should be preloaded.
  radiogroup: ['command'],
  readonly: ['input', 'textarea'], // Indicates whether the element can be edited.
  rel: ['a', 'area', 'link'], // Specifies the relationship of the target object to the link object.
  required: ['input', 'select', 'textarea'], // Indicates whether this element is required to fill out or not.
  reversed: ['ol'], // Indicates whether the list should be displayed in a descending order instead of a ascending.
  rows: ['textarea'], // Defines the number of rows in a text area.
  rowspan: ['td', 'th'], // Defines the number of rows a table cell should span over.
  sandbox: ['iframe'], // scope: ['th'], //scoped: ['style'], //seamless: ['iframe'], //selected: ['option'], //Defines a value which will be selected on page load.
  shape: ['a', 'area'], // size: ['input', 'select'], //Defines the width of the element (in pixels). If the element's type attribute is text or password then it's the number of characters.
  sizes: ['link', 'img', 'source'],
  span: ['col', 'colgroup'], // spellcheck: [Global attribute	Indicates whether spell checking is allowed for the element.
  src: ['audio', 'embed', 'iframe', 'img', 'input', 'script', 'source', 'track', 'video'], // The URL of the embeddable content.
  srcdoc: ['iframe'], // srclang: ['track'], //srcset: ['img'], //start: ['ol'], //Defines the first number if other than 1.
  step: ['input'], // style: [Global attribute	Defines CSS styles which will override styles previously set.
  summary: ['table'], // tabindex: [Global attribute	Overrides the browser's default tab order and follows the one specified instead.
  target: ['a', 'area', 'base', 'form'], // title: [Global attribute	Text to be displayed in a tooltip when hovering over the element.
  type: ['button', 'input', 'command', 'embed', 'object', 'script', 'source', 'style', 'menu'], // Defines the type of the element.
  usemap: ['img', 'input', 'object'], // value: ['button', 'option', 'input', 'li', 'meter', 'progress', 'param'], //Defines a default value which will be displayed in the element on page load.
  width: ['canvas', 'embed', 'iframe', 'img', 'input', 'object', 'video'], // For the elements listed here, this establishes the element's width.
  wrap: ['textarea']
}
