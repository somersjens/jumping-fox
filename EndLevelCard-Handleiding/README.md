# Einde-levelkaart van Jumping Fox

Deze map beschrijft hoe de resultaatkaart van Jumping Fox is opgebouwd. De specificatie is gebaseerd op de actuele implementatie in `GameView.swift` en `Challenges.swift`.

`EndLevelCardExample.swift` is een zelfstandige SwiftUI-versie die je naar een ander iOS-project kunt kopiëren. De namen en modellen zijn bewust algemeen gemaakt; de originele app is niet nodig om het bestand te compileren.

## 1. Opbouw van de kaart

De kaart staat als pop-over boven het nog zichtbare speelveld:

1. Zwarte schermlaag met 56% dekking.
2. Illustratie (trofee bij een voltooid level).
3. Dynamische titel, bijvoorbeeld `+3 afgerond!`.
4. Vaste beschrijving: `Je hebt alle punten gehaald.`
5. Scorecapsule, bijvoorbeeld `20 / 20`.
6. Primaire knop `Nog een keer`.
7. Secundaire knop `Hoofdmenu`.

De inhoud staat in een `ScrollView`. Als de kaart op het scherm past, wordt hij verticaal gecentreerd. Op een compact liggend scherm kan hij scrollen.

```swift
GeometryReader { proxy in
    ScrollView {
        VStack(spacing: 0) {
            illustration
            title
            subtitle
            scoreCapsule
            buttons
        }
        .padding(26 * layoutScale)
        .frame(maxWidth: 400 * layoutScale)
        .background(cardBackground)
        .padding(24) // bewust niet meegeschaald
        .frame(maxWidth: .infinity)
        .frame(minHeight: proxy.size.height, alignment: .center)
    }
    .scrollBounceBehavior(.basedOnSize)
}
```

## 2. Schalen voor iPhone en iPad

De originele kaart gebruikt twee schaalfactoren:

```swift
let layoutScale: CGFloat = isPad ? 1.2 : 1.0
let textScale: CGFloat = isPad ? 1.296 : 1.0
```

`layoutScale` schaalt afmetingen en tussenruimtes. `textScale` maakt tekst op iPad iets groter dan de rest van de kaart. De tabel bevat de werkelijk gerenderde punten vóór eventuele Dynamic Type-aanpassingen.

| Onderdeel | iPhone | iPad | Schaal |
|---|---:|---:|---|
| Maximale kaartbreedte | 400 pt | 480 pt | layout |
| Binnenruimte kaart | 26 pt | 31,2 pt | layout |
| Buitenruimte rond kaart | 24 pt | 24 pt | vast |
| Hoekradius kaart | 28 pt | 28 pt | vast |
| Trofeegebied hoogte | 92 pt | 110,4 pt | layout |
| Trofee-emoji | 70 pt | 84 pt | layout |
| Ruimte illustratie → titel | 18 pt | 21,6 pt | layout |
| Titeltekst | 29 pt | 37,58 pt | tekst |
| Ruimte tussen titelonderdelen | 7 pt | 8,4 pt | layout |
| Beschrijving voltooid level | 17 pt | 22,03 pt | tekst |
| Beschrijving game over | 20 pt | 25,92 pt | tekst |
| Titel → beschrijving | 10 pt | 12 pt | layout |
| Minimale hoogte beschrijving | 30 pt | 36 pt | layout |
| Scoretekst | 30 pt | 38,88 pt | tekst |
| Scorecapsule horizontale padding | 27 pt | 32,4 pt | layout |
| Scorecapsule verticale padding | 10 pt | 12 pt | layout |
| Beschrijving → score | 22 pt | 26,4 pt | layout |
| Score → knoppen | 24 pt | 28,8 pt | layout |
| Ruimte tussen knoppen | 12 pt | 14,4 pt | layout |
| Verticale knop-padding | 14 pt | 16,8 pt | layout |
| Hoekradius knoppen | 17 pt | 17 pt | vast |

De kaart heeft een schaduw met zwart op 22% dekking, radius 24 pt en een verticale verplaatsing van 12 pt. De kaart heeft een witte rand van 1 pt op 82% dekking.

## 3. Kleuren en typografie

De kleuren komen uit het actieve karakterthema:

- kaartachtergrond: verticale gradient `skyColor → wit → tintColor`;
- titel: `deepColor`;
- beschrijving: `deepColor` op 64% dekking;
- scoretekst: `color`;
- scorecapsule: `tintColor`, met een rand van `color` op 12%;
- primaire knop: verticale gradient `color → deepColor`, witte tekst;
- secundaire knop: `skyColor`, tekst in `deepColor`, rand in `color` op 24%.

De titel, score en breuk gebruiken het afgeronde systeemlettertype met gewicht `.heavy`. De beschrijving gebruikt het gewone systeemlettertype:

```swift
let titleFont = Font.system(
    size: 29 * textScale,
    weight: .heavy,
    design: .rounded
)

let subtitleFont = Font.system(
    size: 17 * textScale,
    weight: .medium
)

let scoreFont = Font.system(
    size: 30 * textScale,
    weight: .heavy,
    design: .rounded
)
```

De titel blijft op één regel en mag tot 72% van zijn normale grootte krimpen:

```swift
.lineLimit(1)
.minimumScaleFactor(0.72)
```

## 4. Hoe de titel uit het level wordt gemaakt

Een level bevat minimaal deze gegevens:

```swift
struct Level {
    let category: LevelCategory
    let index: Int
    let cardNumber: String
    let mode: PracticeMode
}
```

Belangrijk: de titel gebruikt `cardNumber`, niet `index`. `index` identificeert de positie van het level; `cardNumber` is de zichtbare rekenwaarde. Voor een breukenlevel kan level 3 bijvoorbeeld `cardNumber == "4"` hebben en wordt de titel `1/4 afgerond!`.

| Categorie | Titelvorm | Voorbeeld bij `cardNumber = "7"` |
|---|---|---|
| optellen / optelmix | `+n` | `+7 afgerond!` |
| aftrekken / aftrekmix | `−n` | `−7 afgerond!` |
| tafels / tafelmix | `×n` | `×7 afgerond!` |
| procenten / procentmix | `n%` | `7% afgerond!` |
| breuken / breukenmix | gestapeld `1` boven `n` | `1/7 afgerond!` |
| Supermix | `n` plus gevulde ster | `7 ★ afgerond!` |

```swift
switch level.category {
case .addition, .additionMix:
    Text("+\(level.cardNumber)")
case .subtraction, .subtractionMix:
    Text("−\(level.cardNumber)")
case .tables, .tablesMix:
    Text("×\(level.cardNumber)")
case .percentages, .percentagesMix:
    Text("\(level.cardNumber)%")
case .fractions, .fractionsMix:
    stackedFraction(numerator: "1", denominator: level.cardNumber)
case .supermix:
    HStack { Text(level.cardNumber); Image(systemName: "star.fill") }
}

Text(localizedCompletionSuffix) // Nederlands: "afgerond!"
```

De breuk is geen plat tekstlabel. Teller en noemer staan verticaal met een lijn ertussen. De cijfers zijn 60% van de titelgrootte; de breuklijn is `max(2 pt, titelgrootte × 0,07)` dik.

## 5. Hoe de beschrijving wordt gekozen

Bij een voltooid level verandert de beschrijving **niet** per categorie of level. Alleen de titel en het scoredoel zijn level-afhankelijk.

```swift
let completionSubtitle = String(localized: "game.end.completionSubtitle")
// Nederlands: "Je hebt alle punten gehaald."
```

Dezelfde kaart wordt ook gebruikt wanneer de speler af is. Dan is de titel `Game over` en wordt de beschrijving op basis van de behaalde score gekozen:

```swift
let messageIndex = min(max(score, 0) / 3, 9)
let messageKey = "game.encouragement.\(messageIndex)"
```

Door gehele deling ontstaan deze bereiken:

| Score | Nederlandse beschrijving |
|---:|---|
| 0–2 | Goed geprobeerd |
| 3–5 | Het begin is er |
| 6–8 | Blijf oefenen |
| 9–11 | Lang niet slecht |
| 12–14 | Goed bezig |
| 15–17 | Mooie prestatie |
| 18–20 | Knap gedaan |
| 21–23 | Heel goed gespeeld |
| 24–26 | Het einde is in zicht |
| 27 en hoger | Je bent er bijna |

De game-overbeschrijving is daarom groter en zwaarder (`20 pt`, semibold) dan de vaste voltooiingsbeschrijving (`17 pt`, medium).

## 6. Scoredoel op basis van het level

De noemer in `score / doel` wordt bepaald door de speelmodus. Supermix vormt een uitzondering:

```swift
func trophyGoal(for level: Level) -> Int {
    if level.category == .supermix { return 50 }

    switch level.mode {
    case .order:  return 20
    case .random: return 30
    case .mixed:  return 40
    }
}
```

De tekst wordt altijd links-naar-rechts gehouden, ook in een rechts-naar-linkstaal, zodat `20 / 20` niet omdraait:

```swift
Text("\(score) / \(goal)")
    .environment(\.layoutDirection, .leftToRight)
```

## 7. Animaties en gedrag

- De zwarte achtergrond animeert in 0,24 seconde naar 56% dekking.
- De kaart begint op schaal 0,93 en 18 pt lager.
- De kaart verschijnt met een spring: response 0,46 en damping 0,82.
- De trofee begint op schaal 0,4 en −25 graden en springt naar schaal 1 en 0 graden: response 0,55 en damping 0,5.
- Confetti start 0,34 seconde na het presenteren van het eindscherm.
- Een nieuw-recordbadge verschijnt na 0,5 seconde, uitsluitend bij een strikt hoger eerder record en een score boven nul.

```swift
.opacity(isVisible ? 1 : 0)
.scaleEffect(isVisible ? 1 : 0.93)
.offset(y: isVisible ? 0 : 18)
.animation(
    .spring(response: 0.46, dampingFraction: 0.82),
    value: isVisible
)
```

## 8. Overnemen in een andere app

1. Kopieer `EndLevelCardExample.swift` naar het nieuwe Xcode-project.
2. Vervang `EndLevel` en `EndLevelCategory` door je eigen levelmodel, of maak een mapper.
3. Vul `EndCardPalette` met de kleuren van je app.
4. Lever gelokaliseerde teksten aan voor `completionSuffix`, `completionSubtitle`, `playAgainTitle` en `menuTitle`.
5. Roep de kaart aan in een overlay en geef de twee knopacties mee.

```swift
EndLevelCard(
    level: currentLevel,
    score: currentScore,
    palette: appPalette,
    showsNewHighScore: didBeatRecord,
    onPlayAgain: restartLevel,
    onMenu: returnToMenu
)
```

Als de andere app geen iPad-versie heeft, kun je `layoutScale` en `textScale` allebei permanent op `1` zetten.
