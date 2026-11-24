using System.Net;
using System.Text.RegularExpressions;

namespace iSupportArchiveV2.Services;

/// <summary>
/// iSupport stored many descriptions, resolutions and comments as HTML from its editor (&lt;p&gt;, &amp;nbsp;, inline
/// styles). This turns them into readable plain text, keeping paragraph and line breaks. The HTML itself is never put
/// on the page: it was typed by users of the old system, so showing it as-is wouldn't be safe.
/// </summary>
public static partial class PlainText
{
    /// <summary>Readable text with line breaks (the ticket page).</summary>
    public static string FromHtml(string? html)
    {
        if (string.IsNullOrWhiteSpace(html)) return "";
        var text = Comments().Replace(html, "");
        text = Breaks().Replace(text, "\n");
        text = Tags().Replace(text, "");
        text = WebUtility.HtmlDecode(text).Replace(' ', ' ');
        text = SpacesBeforeBreak().Replace(text, "\n");
        text = ManyBreaks().Replace(text, "\n\n");
        return text.Trim();
    }

    /// <summary>The same on one line (the ticket list).</summary>
    public static string OneLine(string? html) => Whitespace().Replace(FromHtml(html), " ");

    [GeneratedRegex("<!--.*?-->", RegexOptions.Singleline)]
    private static partial Regex Comments();

    // line breaks, and the ends of paragraphs, list items, rows and other blocks
    [GeneratedRegex(@"<br\s*/?>|</(p|div|li|tr|h[1-6]|blockquote|pre|table|ul|ol)\s*>", RegexOptions.IgnoreCase)]
    private static partial Regex Breaks();

    [GeneratedRegex("<[^>]*>")]
    private static partial Regex Tags();

    [GeneratedRegex(@"[ \t]+\n")]
    private static partial Regex SpacesBeforeBreak();

    [GeneratedRegex(@"\n{3,}")]
    private static partial Regex ManyBreaks();

    [GeneratedRegex(@"\s+")]
    private static partial Regex Whitespace();
}
