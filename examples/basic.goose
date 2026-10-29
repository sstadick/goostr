import goostr from "..";
import goosimd from "github.com/sstadick/goosimd@a619a2e1d6c194be4555b01beb63ef2042131ad3";

fn main() {
    let data = "  name=goose\xFF\r\n  count=42\n";
    goostr::lines(data) { line =>
        let key, value, found = goostr::split_once_str(goostr::trim(line), "=");
        if found { print(key, ": ", goostr::to_str_lossy(value)); }
    }
    print(goostr::replace("a\0b\0c", "\0", " / "));
    goostr::char_indices("a☃\xE2\x98!") { start, end, cp =>
        print(start, "..", end, ": ", cp);
    }
}
