typedef unsigned int size_t;
typedef unsigned int uint32_t;

extern void printhex(unsigned int);
#define LEN 16384
uint32_t list[LEN];
#define SWAP(x, y) { uint32_t z = x; x = y; y = z; }

static void bubblesort ()
{
    int change;
    do
    {
        change = 0;
        for (size_t i = 0; i < LEN-1; i++)
        {
            if (list[i] > list[i+1])
            {
                SWAP(list[i], list[i+1]);
                change = 1;
            }
        }
        
    } while (change);
}

static int partition (int p, int r) {
    uint32_t x = list[r];
    int i = p - 1;
    for (int j = p; j < r; j++)
    {
        if (list[j] <= x) 
        {
            i++;
            SWAP(list[i], list[j]); 
        }
    }
    i++;
    SWAP(list[i], list[r]);
    return i;
}
static void quick_sort (int p, int r) {
    if (p < r)
    {
        int q = partition(p, r);
        quick_sort(p, q - 1);
        quick_sort(q + 1, r);
    }
}

int main ()
{
    
    uint32_t seed = 0xdeadbeef;
    for (size_t i = 0; i < LEN; i++)
    {
        list[i] = seed;
        seed ^= seed << 13;
        seed ^= seed >> 17;
        seed ^= seed << 5;
    }
    
    quick_sort(0, LEN-1);
        
    for (int i = 0; i < LEN; i++)
        printhex(list[i]);
    
    
    return 0;
}
