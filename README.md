# Ajopäiväkirja

Android-sovellus työmatkojen kilometrikorvausten ja päivärahojen
kirjaamiseen. Tiedot tallennetaan paikallisesti ja viedään Google
Sheetsiin, CSV-tiedostoon tai PDF-raportiksi.

## Miten se toimii

1. **Määrittele reitit** – Lisää vakituiset ajoreitit (esim. Koti ↔
   Toimisto) ja niiden pituudet reittienhallinnassa.
2. **Aloita ajo** – Paina aloitusnappia reitin kohdalla ja syötä
   matkamittarin lukema – joko käsin tai **kuvaamalla mittari**
   (ML Kit -tekstintunnistus täyttää lukeman automaattisesti).
3. **Lopeta ajo** – Saavuttuasi perille sovellus tallentaa ajan ja
   laskee korvaukset.
4. **Vapaa ajo ilman reittiä** – "Aloita ajo" kysyy lähtö- ja
   määränpaikan, ajan, mittarilukeman ja tarkoituksen, ja tallentaa
   matkan myös uudeksi uudelleenkäytettäväksi reitiksi.
5. **Lisää kuluja** – Voit liittää ajopäivään kuluja (pysäköinti,
   tietulli, ateria, muu).
6. **Jos unohdat lopettaa** – Sovellus muistuttaa ilmoituksella
   (GPS-pohjainen + aikaperusteinen).
7. **Päivän päätteeksi** – Kun palaat kotiin, sovellus laskee
   päivärahan (6 h / 10 h rajat) ja voit viedä rivit Google Sheetsiin,
   CSV-tiedostoon tai PDF-raporttiin.

Sovellus muistaa edellisen saapumispaikan ja täyttää lähtöpaikan
automaattisesti. Käyttäjätieto ja reittikohtainen tarkoitus
täydennetään muistista.

## Tekninen rakenne

| Osa | Teknologia |
|-----|-----------|
| Sovelluskehys | Flutter (Dart, SDK ^3.11.5) |
| Tilankäsittely | Riverpod |
| Paikallinen tietokanta | sqflite (SQLite) |
| Google-integraatio | googleapis + google_sign_in |
| Taustapalvelu | flutter_background_service |
| Sijainti | geolocator (GPS + geofencing) |
| Ilmoitukset | flutter_local_notifications |
| Mittarin kuvantunnistus | google_mlkit_text_recognition + image_picker |
| CSV/PDF-vienti | pdf + printing + share_plus + open_filex |

### Kansiorakenne

```
lib/
├── main.dart                       # Sovelluksen käynnistys, teema, ProviderScope
├── app_version.dart                # Git-tagista generoitu versiotieto
├── models/                         # Tietomallit
│   ├── route.dart                  # Reitti: nimi, alku/loppu, pituus, muistettu tarkoitus
│   ├── trip_leg.dart               # Ajoleg: ajat, mittarilukemat, korvaukset
│   ├── app_settings.dart           # Asetukset: km-korvaus, päivärahat, Sheets-tunnus
│   ├── km_rate.dart                # Vuosikohtaiset kilometrikorvaukset
│   ├── expense.dart                # Kulu: tyyppi, summa, kuvaus
│   └── location_zone.dart          # Nimetty sijaintialue (geofence)
├── services/                       # Liiketoimintalogiikka
│   ├── database_service.dart       # sqflite CRUD-operaatiot ja migraatiot
│   ├── trip_calculator.dart        # Korvauslaskenta (km + päiväraha)
│   ├── sheets_service.dart         # Google Sheets API -integrointi
│   ├── csv_export_service.dart     # CSV-vienti (UTF-8 BOM, CRLF)
│   ├── pdf_report_service.dart     # PDF-raportin generointi
│   ├── file_opener_service.dart    # Tiedoston avaus / jako / tallennus
│   ├── odometer_vision_service.dart# Mittarilukeman tunnistus kuvasta
│   ├── location_service.dart       # GPS ja geofencing
│   ├── trip_detection_service.dart # Automaattinen ajon tunnistus
│   ├── background_service.dart     # Taustapalvelun hallinta
│   ├── notification_service.dart   # Ilmoitukset
│   └── log_service.dart            # Diagnostiikkaloki
├── providers/                      # Riverpod-tarjoajat
│   ├── route_provider.dart
│   ├── trip_provider.dart
│   └── settings_provider.dart
├── screens/                        # Näkymät
│   ├── home_screen.dart            # Päänäkymä: viimeisimmät reitit, päivän yhteenveto
│   ├── route_management_screen.dart# Reittien lisäys ja muokkaus
│   ├── settings_screen.dart        # Asetukset
│   └── trip_history_screen.dart    # Historia ja vienti (Sheets/CSV/PDF)
└── widgets/                        # Uudelleenkäytettävät komponentit
    ├── odometer_dialog.dart        # Matkamittarin syöttö (käsin tai kuvasta)
    ├── active_trip_card.dart       # Käynnissä olevan ajon kortti
    ├── expense_dialog.dart         # Kulun syöttö
    └── location_autocomplete.dart  # Sijaintikenttä automaattitäydennyksellä
```

### Tietokantarakenne (SQLite, versio 7)

**routes** – Reitit
| Kenttä | Tyyppi | Kuvaus |
|--------|--------|--------|
| id | INTEGER PK | |
| name | TEXT | Reitin nimi (esim. "Koti ↔ Toimisto") |
| start_location | TEXT | Lähtöpaikka |
| end_location | TEXT | Määränpää |
| distance_km | REAL | Matkan pituus kilometreinä |
| last_purpose | TEXT | Viimeisin käytetty tarkoitus (muistia varten) |
| created_at | TEXT | |
| updated_at | TEXT | |

**trip_legs** – Ajolegit
| Kenttä | Tyyppi | Kuvaus |
|--------|--------|--------|
| id | INTEGER PK | |
| date | TEXT | Päivämäärä (yyyy-MM-dd) |
| leg_order | INTEGER | Järjestysnumero päivän sisällä |
| route_id | INTEGER | Viite reittiin (SET NULL poistettaessa) |
| start_time | TEXT | Aloitusaika (ISO 8601) |
| end_time | TEXT | Lopetusaika (ISO 8601) |
| start_odometer | INTEGER | Matkamittarin lukema alussa |
| end_odometer | INTEGER | Matkamittarin lukema lopussa |
| start_location | TEXT | Lähtöpaikka |
| end_location | TEXT | Määränpää |
| route_description | TEXT | Vapaamuotoinen reittikuvaus |
| km_driven | REAL | Ajettu matka |
| working_time_hours | REAL | Työaika määränpäässä |
| leg_duration_hours | REAL | Legin kesto |
| purpose | TEXT | Tarkoitus |
| driver | TEXT | Kuljettaja |
| km_allowance | REAL | Km-korvaus € |
| daily_allowance | REAL | Päiväraha € (vain päivän viimeinen rivi) |
| daily_allowance_type | INTEGER | Päivärahan tyyppi (0/6h/10h) |
| is_return_home | INTEGER | 1 = paluu kotiin |
| synced | INTEGER | 1 = viety Sheetsiin |

**settings** – Asetukset (avain-arvo)

**deleted_leg_ids** – Poistettujen ajolegien tunnukset (Sheets-synkronoinnin siivoamiseen)

**km_rates** – Vuosikohtaiset kilometrikorvaukset
| Kenttä | Tyyppi | Kuvaus |
|--------|--------|--------|
| year | INTEGER PK | Vuosi |
| rate | REAL | Km-korvaus €/km kyseiselle vuodelle |

**expenses** – Kulut
| Kenttä | Tyyppi | Kuvaus |
|--------|--------|--------|
| id | INTEGER PK | |
| trip_leg_id | INTEGER | Viite ajolegiin (SET NULL poistettaessa) |
| type | INTEGER | Kulutyyppi: pysäköinti / tietulli / ateria / muu |
| amount | REAL | Kulun summa € |
| description | TEXT | Kuvaus |
| created_at | TEXT | |

**location_zones** – Nimetyt sijaintialueet
| Kenttä | Tyyppi | Kuvaus |
|--------|--------|--------|
| id | INTEGER PK | |
| name | TEXT | Alueen nimi |
| latitude / longitude | REAL | Keskipiste |
| radius_meters | REAL | Säde metreinä (oletus 200) |
| created_at | TEXT | |

Tietokanta migratoituu automaattisesti vanhoista versioista
(`_onUpgrade`); aiemmat asennukset säilyttävät tietonsa.

## Vienti

Ajohistoriasta voi viedä tiedot kolmella tavalla:

### Google Sheets

Sovellus kirjoittaa rivit seuraaviin sarakkeisiin:

1. Päivämäärä
2. Alkamisaika
3. Alussa (km)
4. Päättymisaika
5. Lopussa (km)
6. Alkamispaikka
7. Päättymispaikka
8. Ajoreitti
9. Matkan pituus
10. Tarkoitus
11. Käyttäjä
12. Km-korvaus €
13. Päiväraha €
14. Yhteensä €
15. Tuntia
16. Työaika

### CSV-tiedosto

CSV-vienti sisältää myös kulurivit ja päivärahatyypin. Tiedosto
kirjoitetaan UTF-8 BOM:lla ja CRLF-rivinvaihdoilla, jotta skandit
(ä/ö/å) näkyvät oikein Excelissä ja Google Sheetsissä. Sarakkeet:

```
Päivämäärä, Järjestys, Lähtöaika, Päättymisaika, Lähtöpaikka,
Määränpää, Reitti, Mittari alussa, Mittari lopussa, Ajetut km,
Tarkoitus, Kuljettaja, Km-korvaus (€), Päiväraha (€),
Päivärahatyyppi, Kotiinpaluu, Tuntia, Työaika,
Tyyppi (kulu/matka), Kulutyyppi, Kulun summa (€), Kulun kuvaus
```

### PDF-raportti

Tulostettava yhteenvetoraportti valitulta ajanjaksolta.

### Vientivalinnat

CSV- ja PDF-tiedoston voi vientidialogissa:

- **Avaa sovelluksessa** – avaa tiedoston suoraan toisessa
  sovelluksessa (esim. Sheets, Excel, PDF-katselin)
- **Jaa** – jakaa tiedoston järjestelmän jakovalikon kautta
- **Tallenna** – tallentaa tiedoston laitteen Downloads-kansioon

## Asetukset

Sovelluksen asetuksista voit määrittää:

- **Kotiosoite** – Päiväraha lasketaan kotoa lähdön ja kotiin paluun väliltä
- **Km-korvaus** (€/km) – Verohallinnon vahvistama kilometrikorvaus,
  vuosikohtaisesti (`km_rates`-taulu, oletukset 2020–2026)
- **Päiväraha yli 6 h** (€) – Osapäiväraha (oletus 25 €)
- **Päiväraha yli 10 h** (€) – Kokopäiväraha (oletus 54 €)
- **Google Sheets ID** – Taulukon tunnus (URL:stä)
- **Välilehti** – Taulukon välilehden nimi (oletus "Taulukko1")
- **Kuljettajan nimi** – Kirjautuu automaattisesti riveille
- **Diagnostiikkaloki** – Lokituksen voi kytkeä päälle vianselvitystä varten

## Korvauslaskenta

### Kilometrikorvaus
```
Per leggi: ajettu matka (km) × ajovuoden km-korvaus (€/km)
```

### Päiväraha
```
Päivän kokonaistunnit = kotiinpaluun aika − kotoalähdön aika

Jos > 10 tuntia → kokopäiväraha (allowance_10h)
Jos > 6 tuntia  → osapäiväraha (allowance_6h)
Muuten          → 0 €

Vain päivän viimeinen rivi saa päivärahan.
```

### Työaika
```
Työaika = saapuminen ensimmäiselle työkohteelle −
          lähtö viimeiseltä työkohteelta
```

## Kehitysympäristö

### Vaatimukset
- Flutter SDK 3.11.5+
- Android Studio (SDK ja build-työkalut)
- Java JDK 17+

### Paikallinen kehitys
```bash
git clone https://github.com/lpalokan/ajopaivakirja.git
cd ajopaivakirja
flutter pub get
flutter run
```

### Valmiit APK:t (GitHub Releases)

Jokainen `main`-haaraan tehty merge rakentaa sekä debug- että
release-APK:n ja julkaisee ne GitHub Releasesissa. Uusin asennettava
versio löytyy aina osoitteesta:

- [Releases](https://github.com/lpalokan/ajopaivakirja/releases) –
  lataa `kilometrikorvaus-…-release.apk` ja asenna laitteelle.

Release-APK allekirjoitetaan toistaiseksi Androidin debug-avaimella,
joten se asentuu mille tahansa laitteelle, mutta päälleasennus jonkin
toisella avaimella allekirjoitetun version päälle vaatii vanhan version
poistamisen ensin.

### Versiointi ja APK:n rakentaminen paikallisesti

Versionumero generoituu git-tageista:

```bash
./scripts/version.sh --release
```

APK tai app bundle rakennetaan `build.sh`-skriptillä. Buildikohde on
pakollinen argumentti:

```bash
./scripts/build.sh apk
./scripts/build.sh apk --debug
./scripts/build.sh appbundle --release
```

Valmis APK syntyy polkuun
`build/app/outputs/flutter-apk/app-release.apk`.

## Automaattitestaus

Projekti on **BDD-first**: jokainen ominaisuus alkaa selkokielisellä
Gherkin-skenaariolla (`integration_test/features/*.feature`), joka ajetaan
Android-emulaattorilla. Testit jakautuvat: nopeat host-testit (yksikkö- ja
widget-testit, Dart-VM, ilman emulaattoria) ja Gherkin-päästä-päähän-testit
emulaattorilla. Täysi ohje ja ylläpito: `docs/testing.md`.

Gherkin-paketin ajo ja raportti:

```bash
./scripts/integration-report.sh
```

Helpoin tapa on apuskripti (idempotentti, turvallinen ajaa uudelleen):

```bash
./scripts/test.sh
./scripts/test.sh --emulator
```

Skripti ei asenna Flutter- tai Android-SDK:ta, vaan tarkistaa ne ja
kertoo mitä puuttuu. Alla manuaaliset vaiheet samoihin asioihin.

### Host-testit (ilman emulaattoria)

```bash
flutter pub get
flutter analyze
flutter test
```

### Emulaattoritesti (macOS)

Vaatii Android SDK:n ja emulaattorin (vakio Android-emulaattori,
QEMU/HVF-pohjainen). Esivalmistelu kerran (Apple Silicon: arm64-v8a,
Intel: x86_64):

```bash
sdkmanager "platform-tools" "emulator" \
  "system-images;android-34;google_apis;arm64-v8a"
avdmanager create avd -n test_pixel \
  -k "system-images;android-34;google_apis;arm64-v8a" -d pixel_6
```

Aja integraatiotesti käynnissä olevalla emulaattorilla:

```bash
flutter emulators --launch test_pixel
flutter test integration_test/app_smoke_test.dart
```

Smoke-testi varmistaa, että sovellus kääntyy ja käynnistyy laitteella
(sqflite ja pluginit alustuvat) ennen kuin testikattavuutta laajennetaan.

## Asennus puhelimeen (ilman kehittäjätilaa)

Puhelinta ei tarvitse laittaa kehittäjätilaan. APK-tiedoston voi asentaa suoraan.

### Kertaluontoinen valmistelu tietokoneella

```bash
./scripts/build.sh apk --release
```

APK-tiedosto syntyy polkuun
`build/app/outputs/flutter-apk/app-release.apk`.

### Asennus puhelimeen

1. **Siirrä APK puhelimeen** – esimerkiksi sähköpostilla, Google Drive -linkillä, USB-kaapelilla (tiedostonsiirto-tilassa) tai Bluetoothilla.

2. **Salli asennus tuntemattomista lähteistä** – Avaa puhelimessa APK-tiedosto (esim. Tiedostot-sovelluksesta). Android kysyy lupaa asentaa tuntemattomista lähteistä. Salli se kyseiselle sovellukselle (esim. Tiedostot tai Chrome).

3. **Asenna** – Jatka asennus loppuun. Sovellus ilmestyy puhelimen sovellusvalikkoon.

> **Huom:** Google Play Protect saattaa varoittaa tuntemattomasta sovelluksesta. Tämä on normaalia itse käännetylle APK:lle. Voit ohittaa varoituksen.

### Päivitys uuteen versioon

Rakenna uusi APK ja asenna se samalla tavalla. Vanha versio korvautuu. Tiedot säilyvät, koska ne on tallennettu puhelimen omaan tietokantaan.

### Kehittäjävaihtoehto (nopeampi)

Jos käytät developeri-tilaa ja USB-kaapelia:
```bash
flutter install
```

## Google API -konfigurointi

Sovellus tarvitsee Google Cloud -projektin toimiakseen Google Sheetsin kanssa.

1. **Luo projekti** [Google Cloud Consolessa](https://console.cloud.google.com)
2. **Ota Sheets API käyttöön** – APIs & Services → Library → hae "Google Sheets API" → Enable
3. **Määritä OAuth consent screen** – APIs & Services → OAuth consent screen
   - User Type: **External**
   - App name: Kilometrikorvaus
   - User support email: oma sähköpostisi
   - Developer contact: oma sähköpostisi
   - Scopes: `.../auth/spreadsheets` (lisätään automaattisesti)
   - Test users: lisää oma sähköpostisi
4. **Luo OAuth Client ID** – APIs & Services → Credentials → Create Credentials → OAuth Client ID
   - Application type: **Android**
   - Name: Kilometrikorvaus
   - Package name: `fi.lpalokan.kilometrikorvaus`
   - SHA-1 certificate fingerprint: hae komennolla (ks. alla)

### SHA-1-sormenjäljen haku

Debug-buildit (paikallinen `flutter run` / `flutter build apk --debug`)
allekirjoitetaan koneen omalla debug-avaimella:
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android 2>/dev/null | grep SHA1
```

Release-buildit (sekä paikalliset että CI) allekirjoitetaan
projektin omalla release-avaimella, jota säilytetään
salaisuudenhallinnassa — ei repossa. SHA-1:n saa kun avain on paikallisessa
koneessa kohdassa `android/keystore/release.jks`:
```bash
keytool -list -v -keystore android/keystore/release.jks -alias release 2>/dev/null | grep SHA1
```

### Release-allekirjoituksen konfigurointi

Release-buildit allekirjoitetaan aina samalla, projektin omalla avaimella —
sekä paikallisesti että GitHub Actions -CI:ssä. Avain ja salasanat
*eivät koskaan* käy repossa: paikallisesti ne ovat git-ignoroidussa
`android/keystore/`-kansiossa, ja CI rakentaa ne uudelleen
GitHub Actions -salaisuuksista joka buildissä.

**GitHub Actions -salaisuudet** (Settings → Secrets and variables → Actions → New repository secret):

| Salaisuus | Arvo |
|-----------|------|
| `RELEASE_KEYSTORE_BASE64` | `base64 -w0 android/keystore/release.jks` -tulos yhdellä rivillä |
| `RELEASE_KEYSTORE_PASSWORD` | keystoren salasana |
| `RELEASE_KEY_ALIAS` | avaimen alias (esim. `release`) |
| `RELEASE_KEY_PASSWORD` | avaimen salasana (usein sama kuin keystoren) |

`release.yml`-työnkulku purkaa nämä `android/keystore/release.jks` -tiedostoksi
ja `keystore.properties`-tiedostoksi rakennusvaiheessa ja siivoaa ne
kun runner vapautuu.

**Paikallinen release-build:** sijoita oma kopiosi tiedostoista
`android/keystore/release.jks` ja `android/keystore/keystore.properties`
(esim. `storeFile=release.jks`, `storePassword=…`, `keyAlias=release`,
`keyPassword=…`). Molemmat ovat `.gitignore`ssa. Jos kansio puuttuu,
release-build käyttää debug-avainta — käytännöllistä paikalliseen testaukseen,
mutta tällainen APK ei ole asennettavissa CI:stä tulleen päälle.

**Avaimen varmuuskopiointi on kriittistä.** Jos `release.jks` katoaa ja
sitä ei ole salasanahallinnassa, et voi enää koskaan julkaista
päivityksiä olemassa oleviin asennuksiin — Android hylkää eri
sertifikaatilla allekirjoitetun APK:n.

**Google OAuth Client ID:** Release-buildilla on yksi vakaa SHA-1, joten
sitä varten riittää yksi Android-tyyppinen OAuth Client ID. Lisää
debug-SHA-1 omaksi Client ID:kseen, jos haluat että `flutter run`
sisäänkirjautuu myös paikallisesti.
