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

void printhex (uint32_t num);

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
