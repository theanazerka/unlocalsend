"""Build the iOS 6 localization resources from the editable TSV catalog."""
from pathlib import Path
import plistlib
root=Path(__file__).resolve().parent.parent
catalogs={language:{} for language in ('ru','en','uk')}
for line in (root/'Assets/Translations.tsv').read_text().splitlines():
    if not line: continue
    key,english,ukrainian=[value.replace('\\n','\n') for value in line.split('|')]
    for language,value in [('ru',key),('en',english),('uk',ukrainian)]:
        catalogs[language][key]=value
for language,catalog in catalogs.items():
    directory=root/'Resources'/(language+'.lproj')
    directory.mkdir(exist_ok=True)
    (directory/'Translations.plist').write_bytes(plistlib.dumps(catalog))
    descriptions={
        'NSPhotoLibraryUsageDescription':catalog['Выбор фото и видео для отправки и сохранение полученных файлов в Фото.'],
        'NSPhotoLibraryAddUsageDescription':catalog['Сохранение полученных фото и видео в Фото.'],
    }
    (directory/'InfoPlist.strings').write_bytes(plistlib.dumps(descriptions))
