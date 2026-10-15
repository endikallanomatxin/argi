colors := import("graphical/colors")
main := () -> (.status_code: Int32 = 0) {
 rgb :: colors.RGBColor = (.r = 1.0, .g = 0.5, .b = 0.0)
 rgba :: colors.RGBAColor = (.r = 1.0, .g = 0.5, .b = 0.0, .a = 1.0)
 if rgb.g != 0.5 { abort }
 if rgba.a != 1.0 { abort }
}
