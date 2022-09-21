typedef unsigned int uint32_t;

static void print (const char* c)
{
    volatile char* out = (char*) 0xff000013;
    while (*c != 0)
        *out = *c++;
}

static const char hexLut[] = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'};
static void printhex (uint32_t num)
{
    volatile char* out = (char*) 0xff000013;
    
    *out = hexLut[(num >> 28) & 0xf];
    *out = hexLut[(num >> 24) & 0xf];
    *out = hexLut[(num >> 20) & 0xf];
    *out = hexLut[(num >> 16) & 0xf];
    *out = hexLut[(num >> 12) & 0xf];
    *out = hexLut[(num >> 8) & 0xf];
    *out = hexLut[(num >> 4) & 0xf];
    *out = hexLut[(num >> 0) & 0xf];
    
    /*for (int i = 7; i >= 0; i--)
    {
        uint32_t c = (num >> (i << 2)) & 0xff;
        if (c <= 9)
            *out = c | '0';
        else
            *out = c | 'a';
    }*/
}

int main ()
{
    print("Hello, World!\n");
    for (int i = 0; i < 10; i++)
    {
        printhex(i);
        print("\n");
    }
}
