app [main!] { pf: platform "./platform/main.roc" }

import pf.Stdin
import pf.Stdout

# Float arithmetic and comparisons at both widths, driven by a runtime value
# so they reach the backends instead of being folded.

yes_no : Bool -> Str
yes_no = |b| if b "yes" else "no"

main! = || {
    n = match U8.from_str(Stdin.line!()) {
        Ok(number) => number
        Err(_) => 0
    }
    x = n.to_f64() + 0.5
    y = n.to_f64() - 1.0
    a = x.to_f32_wrap()
    b = y.to_f32_wrap()
    i = n.to_i64() - 5
    j = n.to_i32() - 5

    Stdout.line!("f64: ${(x / y).to_str()} ${(-x).to_str()} ${x.abs().to_str()}")
    Stdout.line!("f32: ${(a + b).to_str()} ${(a - b).to_str()} ${(a * b).to_str()} ${(a / b).to_str()} ${(-a).to_str()}")
    Stdout.line!("lte: ${yes_no(y <= x)} ${yes_no(x <= y)} ${yes_no(i <= 0)} ${yes_no(i <= -3)} ${yes_no(j <= 0)} ${yes_no(j <= -3)}")
}
