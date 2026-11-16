
#!/data/data/com.termux/files/usr/bin/bash
# Setup for the "get" downloader (Termux + yt-dlp)

pkg update -y
pkg install -y python ffmpeg curl
pip install -U yt-dlp
[ -d /sdcard ] || termux-setup-storage

# ---------- ~/.get_q.py ----------
cat > ~/.get_q.py << 'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
fs = d.get("formats", []) or []
dur = d.get("duration") or 0
def sz(f):
    s = f.get("filesize") or f.get("filesize_approx")
    if not s and f.get("tbr") and dur:
        s = f["tbr"] * 1000 / 8 * dur
    return s
audio = [sz(f) for f in fs if f.get("vcodec") == "none" and f.get("acodec") not in (None, "none")]
audio = [a for a in audio if a]
a = max(audio) if audio else 0
best = {}
for f in fs:
    h = f.get("height")
    if not h or f.get("vcodec") in (None, "none"):
        continue
    s = sz(f)
    if f.get("acodec") in (None, "none") and s:
        s += a
    if h not in best or (s or 0) > (best[h] or 0):
        best[h] = s
for h in sorted(best, reverse=True):
    s = best[h]
    print(h, "?" if not s else round(s / 1048576, 1))
PYEOF

# ---------- ~/get.sh ----------
cat > ~/get.sh << 'EOF'
get() {
  local url="$1" folder base start end log first=1 ask=1
  local fmt="bv*+ba/b" choice h s i first_url
  local -a Q arrh arrs
  if [ -z "$url" ]; then
    echo "Usage: get URL"
    return 1
  fi
  case "$url" in
    *tiktok.com*) folder="TikTok"; ask=0 ;;
    *facebook.com*|*fb.watch*|*fb.com*) folder="Facebook"; ask=0 ;;
    *pinterest.*|*pin.it*) folder="Pinterest"; ask=0 ;;
    *twitter.com*|*://x.com/*|*://www.x.com/*|*://mobile.x.com/*) folder="X"; ask=0 ;;
    *xhamster*) folder="XHamster" ;;
    *pornhub.*) folder="Pornhub" ;;
    *youtube.com*|*youtu.be*) folder="YouTube" ;;
    *) folder=$(echo "$url" | sed -E 's#^https?://(www\.)?([^/]+).*#\2#') ;;
  esac
  base="/sdcard/Download/$folder"

  if [ "$ask" = 1 ]; then
    echo -e "\033[36mFetching exact sizes, please wait...\033[0m"
    first_url=$(yt-dlp --flat-playlist --playlist-items 1 --no-warnings --print url "$url" 2>/dev/null | head -1)
    [ -z "$first_url" ] && first_url="$url"
    yt-dlp -J --no-warnings --no-playlist "$first_url" 2>/dev/null > ~/.get_info.json
    mapfile -t Q < <(python3 ~/.get_q.py ~/.get_info.json)

    if [ ${#Q[@]} -eq 0 ]; then
      echo -e "\033[33mCould not read qualities, using Best.\033[0m"
    else
      echo
      echo -e "\033[36mSelect Video Quality:\033[0m"
      i=1
      for line in "${Q[@]}"; do
        read -r h s <<< "$line"
        arrh+=("$h"); arrs+=("$s")
        if [ "$s" = "?" ]; then
          printf '\033[32m%d.\033[0m %sp\n' "$i" "$h"
        else
          printf '\033[32m%d.\033[0m %sp  ->\033[33m %sMB\033[0m\n' "$i" "$h" "$s"
        fi
        i=$((i+1))
      done
      printf '\033[32m%d.\033[0m Best Quality (Default)\n' "$i"
      echo
      read -rp "$(echo -e "\033[36mEnter your choice (1-$i, default $i): \033[0m")" choice
      if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        h="${arrh[choice-1]}"
        fmt="b[height<=$h]/bv*[height<=$h]+ba/b"
      fi
    fi
  fi

  log=$(mktemp)
  echo
  echo "Path: $base/<page name>/"
  echo "URL:  $url"
  echo "-----------------------------"
  start=$(date +%s)
  local tpl="download:%(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s %(info.playlist_index)s %(info.n_entries)s"
  local out="$base/%(uploader,channel,playlist_title|Unknown)s/%(title).100s.%(ext)s"
  PYTHONUNBUFFERED=1 yt-dlp -f "$fmt" --newline --no-colors --ignore-errors --quiet --no-warnings --progress --progress-template "$tpl" --print-to-file "after_move:filepath" "$log" -o "$out" "$url" 2> >(grep -v linker >&2) | while read -r got total est idx n; do
      [ "$total" = "NA" ] && total="$est"
      case "$got" in ''|*[!0-9]*) got=0 ;; esac
      case "$total" in ''|*[!0-9]*) total=0 ;; esac
      case "$idx" in ''|*[!0-9]*) idx=1 ;; esac
      case "$n" in ''|*[!0-9]*) n=1 ;; esac
      [ "$n" -lt 1 ] && n=1
      fp=0
      [ "$total" -gt 0 ] && fp=$(( got * 100 / total ))
      [ "$fp" -gt 100 ] && fp=100
      pct=$(( ((idx - 1) * 100 + fp) / n ))
      fill=$(( pct * 18 / 100 ))
      bar=$(printf '\033[32m%s\033[0m%s' "$(printf '%*s' "$fill" '' | sed 's/ /█/g')" "$(printf '%*s' $(( 18 - fill )) '' | sed 's/ /░/g')")
      [ "$first" = 1 ] && first=0 || printf '\033[2A'
      printf '\033[KDownloading: %d%% [%s]\n\033[KVideo: %s / %s\n' "$pct" "$bar" "$idx" "$n"
    done
  echo
  end=$(date +%s)
  echo "============================="
  echo "Download finished"
  echo "Files:    $(wc -l < "$log")"
  echo "Size:     $(tr '\n' '\0' < "$log" | xargs -0 -r du -ch 2>/dev/null | tail -1 | cut -f1)"
  echo "Duration: $(( end - start )) sec"
  echo "Location: $base"
  rm -f "$log"
}
EOF

# ---------- load automatically in every Termux session ----------
grep -q 'source ~/get.sh' ~/.bashrc 2>/dev/null || echo 'source ~/get.sh' >> ~/.bashrc

echo
echo "Done. Close and reopen Termux, then: get URL"
