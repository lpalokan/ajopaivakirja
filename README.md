# Kilometrikorvaus

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
- Android Studio / VS Code
- Android-laite tai emulaattori

### Asennus
```bash
git clone <repo-url>
cd kilometrikorvaus
flutter pub get
flutter run
```

### Google API -konfigurointi
1. Luo projekti [Google Cloud Consolessa](https://console.cloud.google.com)
2. Ota käyttöön Google Sheets API ja Google Sign-In
3. Lisää OAuth 2.0 Client ID (Android)
4. Lisää SHA-1-sormenjälki (`keytool -list -v -keystore ~/.android/debug.keystore`)
5. Määritä `google-services.json` android/app-kansioon
