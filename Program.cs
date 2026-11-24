using iSupportArchiveV2.Components;
using iSupportArchiveV2.Data;
using iSupportArchiveV2.Services;
using Microsoft.EntityFrameworkCore;
using R2.Web;

var builder = WebApplication.CreateBuilder(args);

// R2Platform: sign-in (students kept out), the layout and banners. The app has one page (the ticket list, Home) and
// no roles, so no menu items.
builder.AddR2Web(web => { });

// iSupport_Archive on sql1, only ever read
builder.Services.AddDbContextFactory<ArchiveDb>(o => o
    .UseSqlServer(builder.Configuration.GetConnectionString("Default")
        ?? throw new InvalidOperationException("No connection string named 'Default' (iSupport_Archive); see README.md."))
    .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
builder.Services.AddSingleton<StaffGroup>();
builder.Services.AddScoped<Archive>();

builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
    app.UseHsts();
}
app.UseStatusCodePagesWithReExecute("/not-found", createScopeForStatusCodePages: true);

app.UseR2Web();
app.UseAntiforgery();

app.MapStaticAssets();
app.MapR2Web();

// An attachment, downloaded: the same check as the ticket page (staff, or the ticket's own customer). No
// RequireAuthorization() here on purpose: R2.Web's fallback policy (signed in, not a student) applies only to endpoints
// without their own rule.
app.MapGet("/download", async (string number, string name, HttpContext http, Archive archive) =>
{
    var viewer = await archive.ViewerAsync(http.User);
    var file = await archive.GetAttachmentAsync(viewer, number, name);
    return file is null ? Results.NotFound() : Results.File(file.FileData, "application/octet-stream", file.FileName);
});

app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode()
    .AddAdditionalAssemblies(typeof(R2WebExtensions).Assembly);

app.Run();
