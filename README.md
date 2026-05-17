# Ajopäiväkirja

Android-sovellus työmatkojen kilometrikorvausten ja päivärahojen kirjaamiseen. Tiedot tallennetaan paikallisesti ja viedään Google Sheets -taulukkoon.

## Miten se toimii

1. **Määrittele reitit** – Lisää vakituiset ajoreitit (esim. Koti ↔ Toimisto) ja niiden pituudet.
2. **Aloita ajo** – Paina aloitusnappia reitin kohdalla ja syötä matkamittarin lukema.
3. **Lopeta ajo** – Saavuttuasi perille sovellus tallentaa ajan ja laskee korvaukset.
4. **Jos unohdat lopettaa** – Sovellus muistuttaa ilmoituksella (GPS-pohjainen + aikaperusteinen).
5. **Päivän päätteeksi** – Kun palaat kotiin, sovellus laskee päivärahan (6h / 10h rajat) ja kirjoittaa kaikki rivit Google Sheetsiin.

Sovellus muistaa edellisen saapumispaikan ja täyttää lähtöpaikan automaattisesti. Käyttäjätieto ja reittikohtainen tarkoitus täydennetään muistista.

## Tekninen rakenne

| Osa | Teknologia |
|-----|-----------|
| Sovelluskehys | Flutter (Dart) |
| Tilankäsittely | Riverpod |
| Paikallinen tietokanta | sqflite (SQLite) |
| Google-integraatio | googleapis + google_sign_in |
| Taustapalvelu | flutter_background_service |
| Sijainti | geolocator (GPS + geofencing) |
| Ilmoitukset | flutter_local_notifications |

### Kansiorakenne

```
lib/
├── main.dart                  # Sovelluksen käynnistys, teema, ProviderScope
├── models/                    # Tietomallit
│   ├── route.dart             # Reitti: nimi, alku/loppu, pituus, muistettu tarkoitus
│   ├── trip_leg.dart          # Ajoleg: ajat, mittarilukemat, korvaukset
│   └── app_settings.dart      # Asetukset: km-korvaus, päivärahat, Sheets-tunnus
├── services/                  # Liiketoimintalogiikka
│   ├── database_service.dart  # sqflite CRUD-operaatiot
│   ├── trip_calculator.dart   # Korvauslaskenta (km + päiväraha)
│   ├── sheets_service.dart    # Google Sheets API -integrointi
│   ├── location_service.dart  # GPS ja geofencing
│   └── notification_service.dart # Ilmoitukset
├── providers/                 # Riverpod-tarjoajat
│   ├── route_provider.dart
│   ├── trip_provider.dart
│   └── settings_provider.dart
├── screens/                   # Näkymät
│   ├── home_screen.dart       # Päänäkymä: kaksi viimeisintä reittiä, päivän yhteenveto
│   ├── settings_screen.dart   # Asetukset
│   └── trip_history_screen.dart # Historia
└── widgets/                   # Uudelleenkäytettävät komponentit
    └── odometer_dialog.dart   # Matkamittarin syöttö
```

### Tietokantarakenne (SQLite)

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
| route_id | INTEGER | Viite reittiin |
| start_time | TEXT | Aloitusaika (ISO 8601) |
| end_time | TEXT | Lopetusaika (ISO 8601) |
| start_odometer | INTEGER | Matkamittarin lukema alussa |
| end_odometer | INTEGER | Matkamittarin lukema lopussa |
| start_location | TEXT | Lähtöpaikka |
| end_location | TEXT | Määränpää |
| km_driven | REAL | Ajettu matka |
| working_time_hours | REAL | Työaika määränpäässä |
| leg_duration_hours | REAL | Legin kesto |
| purpose | TEXT | Tarkoitus |
| driver | TEXT | Kuljettaja |
| km_allowance | REAL | Km-korvaus € |
| daily_allowance | REAL | Päiväraha € (vain päivän viimeinen rivi) |
| is_return_home | INTEGER | 1 = paluu kotiin |
| synced | INTEGER | 1 = viety Sheetsiin |

**settings** – Asetukset (avain-arvo)
| Avain | Kuvaus |
|-------|--------|
| home_location | Kotiosoite (päivärahan rajaamiseen) |
| km_rate | Km-korvaus €/km |
| allowance_6h | Päiväraha yli 6h reissulla |
| allowance_10h | Päiväraha yli 10h reissulla |
| sheet_id | Google Sheets -tiedoston ID |
| sheet_tab | Välilehden nimi |
| driver_name | Kuljettajan nimi |

## Google Sheets -integraatio

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

## Asetukset

Sovelluksen asetuksista voit määrittää:

- **Kotiosoite** – Päiväraha lasketaan kotoa lähdön ja kotiin paluun väliltä
- **Km-korvaus** (€/km) – Verohallinnon vahvistama kilometrikorvaus
- **Päiväraha yli 6h** (€) – Kokopäiväraha
- **Päiväraha yli 10h** (€) – Täysi päiväraha
- **Google Sheets ID** – Taulukon tunnus (URL:stä)
- **Välilehti** – Taulukon välilehden nimi
- **Kuljettajan nimi** – Kirjautuu automaattisesti riveille

## Korvauslaskenta

### Kilometrikorvaus
```
Per leggi: ajettu matka (km) × km-korvaus (€/km)
```

### Päiväraha
```
Päivän kokonaistunnit = kotiinpaluun aika − kotoalähdön aika

Jos > 10 tuntia → täysi päiväraha (allowance_10h)
Jos > 6 tuntia  → kokopäiväraha (allowance_6h)
Muuten         → 0 €

Vain päivän viimeinen rivi saa päivärahan.
```

### Työaika
```
Työaika per leggi = seuraavan legin aloitusaika − tämän legin lopetusaika
(0 jos määränpää on koti)
```

## Kehitysympäristö

### Vaatimukset
- Flutter SDK 3.11+
- Android Studio (SDK ja build-työkalut)
- Java JDK 17+

### Paikallinen kehitys
```bash
git clone https://github.com/lpalokan/mileage-tracker.git
cd mileage-tracker
flutter pub get
flutter run          # Vaatii puhelimen kytkettynä USB:llä (developeri-tila)
```

## Automaattitestaus

Projekti on **BDD-first**: jokainen ominaisuus alkaa selkokielisellä
Gherkin-skenaariolla (`integration_test/features/*.feature`), joka ajetaan
Android-emulaattorilla. Testit jakautuvat: nopeat host-testit (yksikkö- ja
widget-testit, Dart-VM, ilman emulaattoria) ja Gherkin-päästä-päähän-testit
emulaattorilla. Täysi ohje ja ylläpito: `docs/testing.md`.

Gherkin-paketin ajo ja raportti:

```bash
./scripts/integration-report.sh   # build_runner + emulaattoriajo + raportti
```

Helpoin tapa on apuskripti (idempotentti, turvallinen ajaa uudelleen):

```bash
./scripts/test.sh              # host-testit (pub get, analyze, flutter test)
./scripts/test.sh --emulator   # luo myös AVD:n ja ajaa emulaattoritestin
```

Skripti ei asenna Flutter- tai Android-SDK:ta, vaan tarkistaa ne ja
kertoo mitä puuttuu. Alla manuaaliset vaiheet samoihin asioihin.

### Host-testit (ilman emulaattoria)

```bash
flutter pub get
flutter analyze
flutter test          # test/ – TripCalculator, mallit, OdometerDialog
```

### Emulaattoritesti (macOS)

Vaatii Android SDK:n ja emulaattorin (vakio Android-emulaattori,
QEMU/HVF-pohjainen). Esivalmistelu kerran:

```bash
# Apple Silicon: arm64-v8a, Intel: x86_64
sdkmanager "platform-tools" "emulator" \
  "system-images;android-34;google_apis;arm64-v8a"
avdmanager create avd -n test_pixel \
  -k "system-images;android-34;google_apis;arm64-v8a" -d pixel_6
```

Aja integraatiotesti käynnissä olevalla emulaattorilla:

```bash
flutter emulators --launch test_pixel      # tai käynnistä Android Studiosta
flutter test integration_test/app_smoke_test.dart
```

Smoke-testi varmistaa, että sovellus kääntyy ja käynnistyy laitteella
(sqflite ja pluginit alustuvat) ennen kuin testikattavuutta laajennetaan.

## Asennus puhelimeen (ilman kehittäjätilaa)

Puhelinta ei tarvitse laittaa kehittäjätilaan. APK-tiedoston voi asentaa suoraan.

### Kertaluontoinen valmistelu tietokoneella

```bash
# 1. Rakenna release-APK
flutter build apk --release

# APK-tiedosto syntyy tänne:
# build/app/outputs/flutter-apk/app-release.apk
```

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
flutter install   # Asentaa suoraan kytkettyyn puhelimeen
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

```bash
# Debug-avain (kehitys)
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android 2>/dev/null | grep SHA1

# Release-avain (julkaisu)
keytool -list -v -keystore oma-avain.jks -alias avaimen-nimi 2>/dev/null | grep SHA1
```

### Release APK -konfigurointi
Release-versio tarvitsee oman OAuth Client ID:n (eri SHA-1 kuin debug):
1. Luo **toinen** OAuth Client ID -tunnus Android-tyypillä release-SHA-1:llä
2. Lisää molemmat Client ID:t OAuth consent screenin testikäyttäjiin tarvittaessa

