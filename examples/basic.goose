import goostr from "..";

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
