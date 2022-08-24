typedef unsigned int uint32_t;
typedef unsigned int size_t;
uint32_t sieve[128];

void mark (uint32_t prime)
{
    uint32_t iter = prime + (prime >> 1);
    while (1)
    {
        size_t index = iter >> 5;
        if (index >= (sizeof(sieve) / sizeof(sieve[0]))) 
            break;
        
        uint32_t mask = 1U << (iter & 31);
        sieve[index] |= mask;
        
        iter += prime;
    }
}

static const char hexLut[] = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'};
static void printhex (uint32_t num)
{
    volatile char* out = (char*) 1023;
    
    *out = hexLut[(num >> 28) & 0xf];
    *out = hexLut[(num >> 24) & 0xf];
    *out = hexLut[(num >> 20) & 0xf];
    *out = hexLut[(num >> 16) & 0xf];
    *out = hexLut[(num >> 12) & 0xf];
    *out = hexLut[(num >> 8) & 0xf];
    *out = hexLut[(num >> 4) & 0xf];
    *out = hexLut[(num >> 0) & 0xf];
    *out = '\n';
    
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
    uint32_t prime = 3;
    size_t index = 0;
    int bit = 1;

    while (1)
    {
        mark(prime);
        
        while (1)
        {
            while (bit < 31)
            {
                prime += 2;
                bit++;
                if (!(sieve[index] & (1U << bit)))
                    goto found_prime;
            }
            index++;
            bit = -1;
            if (index == (sizeof(sieve) / sizeof(sieve[0]))) 
                return 0;
        }
        
        found_prime:;
        //printf("%.8x\n", prime);
        printhex(prime);
    }
}
