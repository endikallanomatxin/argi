extern int argi_export_sum(int left, int right);
extern void argi_export_set(int *value);
extern double argi_export_float(double left, double right);

int argi_c_probe(void) {
    int value = 0;
    argi_export_set(&value);
    return argi_export_sum(19, 23) == 42 && value == 42 &&
           argi_export_float(1.25, 2.5) == 3.75 ? 0 : 1;
}
