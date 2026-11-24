# Archived iSupport Tickets (iSupportArchiveV2)

A rebuild of the iSupportArchive site on [R2Platform](https://github.com/Richland2/R2Platform): .NET 10 Blazor
Server with Telerik UI for Blazor, Windows sign-in and the district layout. It shows tickets from the old iSupport
helpdesk system, for reference only: nothing in it can be changed.

- **Ticket list** (Home): IT staff (anyone in the `do_it_staff` AD group, including groups inside it) see every
  ticket; everyone else sees only the tickets they opened. Filter, sort, page and export to CSV or Excel, all done
  in SQL so it stays quick.
- **Ticket page** (`tickets/{number}`): details, description and resolution, attachments to download, comments.
  Only staff or the ticket's own customer can open it (or download its files), since numbers are guessable.
- Students can't use the app (R2Platform's student block).

## Data

One database, read only: **`iSupport_Archive` on sql1** (tables `Incidents`, `Comments`, `Files`), the same one the
current site reads. There's no staging copy, so your PC and staging read it too. The app refuses to save to it, and
nothing is added to it: no App Log or audit tables (log entries are skipped; see `R2:Logging` in appsettings.json).

A ticket's customer is stored as an email address (`jdoe@richland2.org`); "your tickets" are those starting with
your account name and `@`.

There are no roles: the app's IntranetSecurity application (`iSupportArchiveV2`) doesn't exist, so nobody has the
admin pages (Manage Users, App Log, Impersonate). Adding it later, with an Admin role, would turn them on.

## First time on a PC

The R2 and Telerik package feeds need your own credentials, saved once in your Windows profile's NuGet settings
(never in this repository). From the R2Platform repository, in PowerShell:

```
powershell -ExecutionPolicy Bypass -File ..\R2Platform\Connect-PackageFeeds.ps1
```

## Running it on your PC

Like the other apps, it runs in your PC's own IIS: **http://localhost:88/iSupportArchiveV2**, always on, with Windows
sign-in. Once, in PowerShell **as Administrator**, from this folder, run this and type the WebAppsUser password when
asked (it doesn't show):

```
powershell -ExecutionPolicy Bypass -File .\Setup-LocalIIS.ps1
```

It creates the `iSupportArchiveV2` app pool and application under your port-88 site, turns on Windows sign-in, and
keeps the connection strings (iSupport_Archive and CommonData on sql1, IntranetSecurity on devdb1, as WebAppsUser) on
the app pool, never in the project.

After that: **build** (Visual Studio's Build, or `dotnet build`), then refresh the page. Each Debug build publishes
the app into `bin\LocalIIS`, which IIS runs it from. If something goes wrong at startup, the details are in the
Windows Event Viewer (Windows Logs > Application, source "IIS AspNetCore Module V2").

The staff check reads the AD group as the app pool's identity (the PC's or server's domain account), once every 15
minutes.

## The server (webapp01)

Not set up yet. When it is: once per environment, on webapp01 in PowerShell as Administrator, from a copy of the
`deploy` folder:

```
powershell -ExecutionPolicy Bypass -File .\Setup-IIS.ps1 -Target Staging
```

It asks for the three connection strings, in the usual form, e.g.
`Server=sql1;Database=iSupport_Archive;User ID=WebAppsUser;Password=...;TrustServerCertificate=true`.
Then deploy from this folder on your PC:

```
powershell -ExecutionPolicy Bypass -File .\deploy\Deploy.ps1                      # staging
powershell -ExecutionPolicy Bypass -File .\deploy\Deploy.ps1 -Target Production   # asks you to confirm
```
