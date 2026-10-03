# Apples Skärmtid i smool

Granskat den 3 oktober 2026 för smools native macOS-app med macOS 26 som mål. Lokal verifiering använde Xcode 27.0, build 27A266a, och macOS SDK 27.0.

## Beslut

Det finns ingen verifierad, stödd publik API-väg för smool att läsa användarens befintliga aggregerade app- och tidsdata från Apples Skärmtid på Mac. Bygg därför ingen Skärmtids-applet nu. Ingen egen tracker, tom rapport, databasläsning eller privat API-integration ingår.

Slutsatsen gäller native macOS och bygger på Apples dokumentation, SDK-deklarationer och kompilatorkontroller mot macOS 26. Att ett ramverk finns i SDK:n betyder inte att dess rapport-API:er får användas på plattformen.

## Vad API:erna faktiskt erbjuder

| API | Verifierad availability | Betydelse för smool |
| --- | --- | --- |
| `ScreenTime.STWebpageController` | macOS 11+ | Rapporterar den egna webbvyns användning och visar blockering av webbsidor. Läser inte systemets appstatistik. |
| `STScreenTimeConfigurationObserver` | macOS 11+ | Observerar konfiguration. `enforcesChildRestrictions` anger om barnrestriktioner gäller, ingen användningstid. |
| `STWebHistory` | macOS 11+; fetch-metoder från macOS 15.4 | Kan hämta webbadresser för angivet bundle-ID och profil. Resultatet är `Set<URL>`, utan appaggregat eller tidslängder. |
| `FamilyControls.AuthorizationCenter` | iOS 15+; explicit unavailable på macOS | Smool kan inte använda det vanliga auktoriseringsflödet för Family Controls. Individuell auktorisering introducerades på iOS 16. |
| `DeviceActivityCenter` | iOS 15+; explicit unavailable på macOS | Scheman och tröskelhändelser ger ingen native Mac-väg till statistiken. |
| `DeviceActivityData`, `DeviceActivityReport`, `DeviceActivityReportExtension`, `DeviceActivityReportScene` | iOS 16+; explicit unavailable på macOS | De datatyper och rapportvyer som skulle behövas går inte att använda i smool. |
| `DeviceActivityAuthorization` | macOS 14+ | Vissa behörighetsfrågor finns, men klassen ger varken rapportdata eller ett publikt samtyckesflöde som gör rapport-API:erna tillgängliga på Mac. |
| `FamilyActivityData`, `approvedWithDataAccess`, `DeviceActivityData.activityData(filteredBy:using:)` | iOS 26.4+; explicit unavailable på macOS och Mac Catalyst | Den nyare direkta dataåtkomsten löser inte smools Mac-behov. |

Tabellens versions- och plattformsuppgifter kommer från den lokala SDK:n. Funktionsbeskrivningarna stämmer med Apples dokumentation för [Screen Time](https://developer.apple.com/documentation/screentime), [STWebpageController](https://developer.apple.com/documentation/screentime/stwebpagecontroller), [STWebHistory](https://developer.apple.com/documentation/screentime/stwebhistory) och [Device Activity](https://developer.apple.com/documentation/deviceactivity). Apple beskriver individuell auktorisering och rapporttillägg i [What's new in Screen Time API, WWDC22](https://developer.apple.com/videos/play/wwdc2022/110336/).

`STWebHistory` ska alltså inte beskrivas som ett rent raderings-API. Dess nyare fetch-metoder finns, men deras returtyp saknar den information användaren vill visa. Ett bundle-ID i en initializer är inte heller belägg för fri åtkomst till andra appars data. `STWebpageController.setBundleIdentifier` dokumenteras för registrerade webbläsares rapportering från hjälpprocesser.

## Samtycke och entitlements

Det vanliga Family Controls-flödet använder `com.apple.developer.family-controls = true`. Distribution kräver Apples godkännande för appens App ID och för varje berört Screen Time-tillägg. Detta entitlement ändrar inte API:ernas plattformsbegränsningar. Se [Configuring Family Controls](https://developer.apple.com/documentation/xcode/configuring-family-controls) och [Requesting the Family Controls entitlement](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement).

Det traditionella `DeviceActivityReport` visar användningsdata via ett särskilt tillägg. Apple beskriver en sandbox som hindrar nätverksanrop och att känsliga data lämnar tilläggets adressrymd. Det är därför inte en generell exportkanal till huvudappen, även på en plattform där rapporten stöds. Se [DeviceActivityReport](https://developer.apple.com/documentation/deviceactivity/deviceactivityreport).

Sedan iOS 26.4 finns även `com.apple.developer.family-controls.app-and-website-usage`. Det möjliggör, efter uttryckligt samtycke, `approvedWithDataAccess` och åtkomst till faktiska appidentifierare, webbdomäner och aktivitetsdata. Apples dokumentation begränsar kundinstallationers sådana godkännande till enheter i EU med ett Apple-konto vars land eller region är inom EU. Endast en app åt gången kan ha denna auktoriseringsstatus. Utveckling och test med Apple-tillhandahållen provisioningprofil har andra regionsvillkor. Se [Family Controls App and Website Usage](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.family-controls.app-and-website-usage) och [approvedWithDataAccess](https://developer.apple.com/documentation/familycontrols/authorizationstatus/approvedwithdataaccess).

De nya API:erna är fortfarande markerade `@available(macOS, unavailable)` i SDK 27.0. Ingen entitlement-ansökan eller ny behörighetsdialog behövs därför för smool i nuläget.

## Lokal verifiering

SDK-roten var:

```text
/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk
```

Följande Apple-filer under `System/Library/Frameworks` granskades:

- `ScreenTime.framework/Headers/STWebpageController.h`
- `ScreenTime.framework/Headers/STWebHistory.h`
- `ScreenTime.framework/Headers/STScreenTimeConfiguration.h`
- `FamilyControls.framework/Modules/FamilyControls.swiftmodule/arm64e-apple-macos.swiftinterface`
- `DeviceActivity.framework/Modules/DeviceActivity.swiftmodule/arm64e-apple-macos.swiftinterface`
- `_DeviceActivity_SwiftUI.framework/Modules/_DeviceActivity_SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`

Två separata Swift-prober kördes med `swiftc -typecheck -target arm64-apple-macosx26.0`. Den första refererade till `STWebpageController`, `STScreenTimeConfigurationObserver`, `STWebHistory` och `DeviceActivityAuthorization` och godkändes. Den andra refererade till `AuthorizationCenter`, `DeviceActivityCenter`, `DeviceActivityData`, `DeviceActivityReport` och `FamilyActivityData`. Kompilatorn avvisade samtliga med `is unavailable in macOS`, vilket bekräftar begränsningen för appens målplattform.

Proberna typkontrollerades utan att köras. Inga samtyckesdialoger öppnades och inga personliga Skärmtidsdata lästes eller ändrades. macOS 26 verifierades som deployment target med SDK 27.0, inte genom en separat installerad SDK 26 eller runtime-prov av Skärmtid.

## När frågan bör tas upp igen

En integration blir aktuell först när Apple publicerar ett macOS-stött sätt att få användarens befintliga app- och tidsaggregat, med ett dokumenterat samtyckesflöde och distributionsstöd. Då bör datatäckning, historik, uppdateringsfrekvens och påverkan på Apples egen Skärmtid verifieras innan en applet planeras. Nuvarande underlag ger ingen sådan integrationsplan.
