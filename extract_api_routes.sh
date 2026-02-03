#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${BASE_DIR}/sources"
OUT_CSV="${BASE_DIR}/api_routes.csv"

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "sources directory not found: ${SRC_DIR}" >&2
  exit 1
fi

TMP_FILE="$(mktemp)"
trap 'rm -f "${TMP_FILE}"' EXIT

find "${SRC_DIR}" -type f -name "*.java" -print0 \
| while IFS= read -r -d '' file; do
  perl -e '
    use strict;
    use warnings;

    my $file = shift;
    open my $fh, "<", $file or die $!;

    my @pending;
    my $current_class = "";
    my $current_base = "";
    my $current_is_controller = 0;
    my $in_annot = 0;
    my $ann_buf = "";

    sub add_annot { push @pending, $_[0]; }
    sub clear_annot { @pending = (); }
    sub has_controller {
      for my $a (@pending) {
        return 1 if $a =~ /\@RestController\b|\@Controller\b/;
      }
      return 0;
    }
    sub extract_paths {
      my ($ann) = @_;
      my $rest = $ann;
      $rest =~ s/^[^(]*\(|\).*$//g;
      my @paths = ($rest =~ /"([^"]+)"/g);
      @paths = ("") unless @paths;
      return @paths;
    }
    sub extract_base {
      my $base = "";
      for my $a (@pending) {
        if ($a =~ /\@RequestMapping\b/) {
          my @p = extract_paths($a);
          $base = $p[0] // "";
        }
      }
      return $base;
    }
    sub extract_methods {
      my ($ann) = @_;
      return ("GET") if $ann =~ /\@GetMapping\b/;
      return ("POST") if $ann =~ /\@PostMapping\b/;
      return ("PUT") if $ann =~ /\@PutMapping\b/;
      return ("DELETE") if $ann =~ /\@DeleteMapping\b/;
      return ("PATCH") if $ann =~ /\@PatchMapping\b/;
      if ($ann =~ /\@RequestMapping\b/) {
        my @m = ($ann =~ /RequestMethod\.([A-Z]+)/g);
        return @m if @m;
      }
      return ("ALL");
    }
    sub join_path {
      my ($base, $path) = @_;
      return $path if $base eq "";
      return $base if $path eq "";
      $base =~ s{/$}{};
      $path = "/$path" unless $path =~ m{^/};
      return $base . $path;
    }

    while (my $line = <$fh>) {
      $line =~ s/\t/ /g;
      chomp $line;

      if ($in_annot) {
        $ann_buf .= " " . $line;
        if ($line =~ /\)/) {
          add_annot($ann_buf);
          $ann_buf = "";
          $in_annot = 0;
        }
        next;
      }

      if ($line =~ /^\s*\@/) {
        if ($line =~ /\(.*\)/ || $line !~ /\(/) {
          add_annot($line);
        } else {
          $ann_buf = $line;
          $in_annot = 1;
        }
        next;
      }

      if ($line =~ /\b(class|interface|enum)\s+([A-Za-z0-9_]+)/) {
        $current_is_controller = has_controller();
        $current_base = extract_base();
        $current_class = $2;
        clear_annot();
        next;
      }

      if ($line =~ /\b(public|protected|private|static|final|synchronized|native|abstract)\b.*\(/) {
        if (!$current_is_controller) {
          clear_annot();
          next;
        }

        my $method_name = "";
        if ($line =~ /\b([A-Za-z0-9_]+)\s*\(/) {
          $method_name = $1;
        }

        for my $ann (@pending) {
          next unless $ann =~ /\@(GetMapping|PostMapping|PutMapping|DeleteMapping|PatchMapping|RequestMapping)\b/;
          my @paths = extract_paths($ann);
          my @methods = extract_methods($ann);
          for my $m (@methods) {
            for my $p (@paths) {
              my $full = join_path($current_base, $p);
              print join("\t", $m, $full, $current_class, $method_name, $file), "\n";
            }
          }
        }
        clear_annot();
        next;
      }
    }
  ' "${file}" >> "${TMP_FILE}"

done

{
  echo "method,path,class,handler,source"
  while IFS=$'\t' read -r method path class handler src; do
    rel="${src#${BASE_DIR}/}"
    printf '%s,%s,%s,%s,%s\n' "${method}" "${path}" "${class}" "${handler}" "${rel}"
  done < "${TMP_FILE}"
} > "${OUT_CSV}"

echo "Wrote ${OUT_CSV}"
