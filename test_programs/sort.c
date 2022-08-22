

static void print(const char* c);
int main();

void _start()
{
    main();
    while (1) ;
}

int main ()
{
    print("Hello, World!\n");
}


static void print (const char* c)
{
    volatile char* out = (char*) 1023;
    while (*c != 0)
        *out = *c++;
}



