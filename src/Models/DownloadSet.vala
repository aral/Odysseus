/**
* This file is part of Odysseus Web Browser (Copyright Adrian Cochrane 2017).
*
* Odysseus is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Odysseus is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.

* You should have received a copy of the GNU General Public License
* along with Odysseus.  If not, see <http://www.gnu.org/licenses/>.
*/
/** Manages a set of Downloads, whilst emitting signals that are easy tie into a
    hierarchical GTK UI.

The maintained set does not include successfully downloaded files, because if those
    are kept in the downloads bar the UI may become cluttered. */
public class Odysseus.DownloadSet : Object {
    public Gee.ArrayList<Download> downloads = new Gee.ArrayList<Download>();
    public virtual signal void add(Download item) {
        downloads.add(item);
        item.cancel.connect(() => downloads.remove(item));
        item.finished.connect(() => downloads.remove(item));
    }

    private static DownloadSet? instance;
    public static DownloadSet get_downloads() {
        if (instance == null) instance = new DownloadSet();
        return instance;
    }

    public static void setup_ctx(WebKit.WebContext ctx) {
        var downloads = get_downloads();
        ctx.download_started.connect((download) => downloads.add(new Download(download)));
    }
}
