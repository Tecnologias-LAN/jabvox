// Jabvox se usa en español e inglés. Antes se importaban los 57 idiomas de forma
// estática, lo que inflaba el bundle compartido (traducciones de todos los locales)
// a ~13 MB que el navegador descargaba incluso en el login. Dejar solo es/en baja
// ese chunk a ~1 MB sin tocar la lógica de carga. Para añadir otro idioma, basta
// con volver a importarlo aquí.
import en from './locale/en';
import es from './locale/es';

export default {
  en,
  es,
};
