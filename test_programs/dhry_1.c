/*
 ****************************************************************************
 *
 *                   "DHRYSTONE" Benchmark Program
 *                   -----------------------------
 *                                                                            
 *  Version:    C, Version 2.1
 *                                                                            
 *  File:       dhry_1.c (part 2 of 3)
 *
 *  Date:       May 17, 1988
 *
 *  Author:     Reinhold P. Weicker
 *
 ****************************************************************************
 */
#include "dhry.h"
#define TIME
/* Global Variables: */
typedef unsigned int uint32_t;
typedef unsigned int size_t;
Rec_Pointer     Ptr_Glob,
                Next_Ptr_Glob;
int             Int_Glob;
Boolean         Bool_Glob;
char            Ch_1_Glob,
                Ch_2_Glob;
int             Arr_1_Glob [50];
int             Arr_2_Glob [50] [50];

char* mallocPtr = (char*)0x20000;
void     *malloc(unsigned long size)
{
  char* retval = mallocPtr;
  mallocPtr += size;
  return retval;
}

extern int strcmp(const char* l, const char* r);

inline  int __attribute__((always_inline)) read_cycles() {
    int result;
    asm("csrr %0, instret" : "=r"(result));
    return result; 
}

inline  int __attribute__((always_inline)) read_time() {
    int result;
    asm("csrr %0, time" : "=r"(result));
    return result; 
}


    
void printf (const char* c, ...)
{
    volatile char* out = (char*) 0xff000003;
    while (*c != 0)
        *out = *c++;
}

static const char hexLut[] = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'};
static void printhex (uint32_t num)
{
    volatile char* out = (char*) 0xff000003;
    
    *out = hexLut[(num >> 28) & 0xf];
    *out = hexLut[(num >> 24) & 0xf];
    *out = hexLut[(num >> 20) & 0xf];
    *out = hexLut[(num >> 16) & 0xf];
    *out = hexLut[(num >> 12) & 0xf];
    *out = hexLut[(num >> 8) & 0xf];
    *out = hexLut[(num >> 4) & 0xf];
    *out = hexLut[(num >> 0) & 0xf];
    
    *out = '\n';
}

extern void printdecu(uint32_t num);

Enumeration     Func_1 ();
  /* forward declaration necessary since Enumeration may not simply be int */

#ifndef REG
        Boolean Reg = false;
#define REG
        /* REG becomes defined as empty */
        /* i.e. no register variables   */
#else
        Boolean Reg = true;
#endif

extern char* strcpy(char *restrict d, const char *restrict s);
/*char* strcpy(char *restrict d, const char *restrict s)
{
	for (; (*d=*s); s++, d++);
	return d;
}*/
                /* see library function "time"  */
#define Too_Small_Time 2
                /* Measurements should last at least 2 seconds */

long            Begin_Time,
                End_Time,
                User_Time;
float           Microseconds,
                Dhrystones_Per_Second;

/* end of variables for time measurement */


int main ()
/*****/

  /* main program, corresponds to procedures        */
  /* Main and Proc_0 in the Ada version             */
{
        One_Fifty       Int_1_Loc;
  REG   One_Fifty       Int_2_Loc;
        One_Fifty       Int_3_Loc;
  REG   char            Ch_Index;
        Enumeration     Enum_Loc;
        Str_30          Str_1_Loc;
        Str_30          Str_2_Loc;
  REG   int             Run_Index;
  REG   int             Number_Of_Runs;

  /* Initializations */

  Next_Ptr_Glob = (void*)0x1F000;
  Ptr_Glob = (void*)0x20000;

  Ptr_Glob->Ptr_Comp                    = Next_Ptr_Glob;
  Ptr_Glob->Discr                       = Ident_1;
  Ptr_Glob->variant.var_1.Enum_Comp     = Ident_3;
  Ptr_Glob->variant.var_1.Int_Comp      = 40;
  strcpy (Ptr_Glob->variant.var_1.Str_Comp,
          "DHRYSTONE PROGRAM, SOME STRING");
  strcpy (Str_1_Loc, "DHRYSTONE PROGRAM, 1'ST STRING");

  Arr_2_Glob [8][7] = 10;
        /* Was missing in published program. Without this statement,    */
        /* Arr_2_Glob [8][7] would have an undefined value.             */
        /* Warning: With 16-Bit processors and Number_Of_Runs > 32000,  */
        /* overflow may occur for this array element.                   */

  printf ("\n");
  printf ("Dhrystone Benchmark, Version 2.1 (Language: C)\n");
  printf ("\n");
  if (Reg)
  {
    printf ("Program compiled with 'register' attribute\n");
    printf ("\n");
  }
  else
  {
    printf ("Program compiled without 'register' attribute\n");
    printf ("\n");
  }
  printf ("Please give the number of runs through the benchmark: ");
  {
    int n=200;
    //scanf ("%d", &n);
    Number_Of_Runs = n;
  }
  printf ("\n");

  printf ("Execution starts, %d runs through Dhrystone\n", Number_Of_Runs);

  /***************/
  /* Start timer */
  /***************/
  
  Begin_Time = read_time();
  uint32_t execdBegin = read_cycles();
  
  for (Run_Index = 1; Run_Index <= Number_Of_Runs; ++Run_Index)
  {

    Proc_5();
    Proc_4();
      /* Ch_1_Glob == 'A', Ch_2_Glob == 'B', Bool_Glob == true */
    Int_1_Loc = 2;
    Int_2_Loc = 3;
    strcpy (Str_2_Loc, "DHRYSTONE PROGRAM, 2'ND STRING");
    Enum_Loc = Ident_2;
    Bool_Glob = ! Func_2 (Str_1_Loc, Str_2_Loc);
      /* Bool_Glob == 1 */
    while (Int_1_Loc < Int_2_Loc)  /* loop body executed once */
    {
      Int_3_Loc = 5 * Int_1_Loc - Int_2_Loc;
        /* Int_3_Loc == 7 */
      Proc_7 (Int_1_Loc, Int_2_Loc, &Int_3_Loc);
        /* Int_3_Loc == 7 */
      Int_1_Loc += 1;
    } /* while */
      /* Int_1_Loc == 3, Int_2_Loc == 3, Int_3_Loc == 7 */
    Proc_8 (Arr_1_Glob, Arr_2_Glob, Int_1_Loc, Int_3_Loc);
      /* Int_Glob == 5 */
    Proc_1 (Ptr_Glob);
    for (Ch_Index = 'A'; Ch_Index <= Ch_2_Glob; ++Ch_Index)
                             /* loop body executed twice */
    {
      if (Enum_Loc == Func_1 (Ch_Index, 'C'))
          /* then, not executed */
        {
        Proc_6 (Ident_1, &Enum_Loc);
        strcpy (Str_2_Loc, "DHRYSTONE PROGRAM, 3'RD STRING");
        Int_2_Loc = Run_Index;
        Int_Glob = Run_Index;
        }
    }
      /* Int_1_Loc == 3, Int_2_Loc == 3, Int_3_Loc == 7 */
    Int_2_Loc = Int_2_Loc * Int_1_Loc;
    Int_1_Loc = Int_2_Loc / Int_3_Loc;
    Int_2_Loc = 7 * (Int_2_Loc - Int_3_Loc) - Int_1_Loc;
      /* Int_1_Loc == 1, Int_2_Loc == 13, Int_3_Loc == 7 */
    Proc_2 (&Int_1_Loc);
      /* Int_1_Loc == 5 */

  } /* loop "for Run_Index" */

  /**************/
  /* Stop timer */
  /**************/
  

  End_Time = read_time();
  uint32_t execdEnd = read_cycles();

  printf ("Execution ends\n");
  printf ("\n");
  printf ("Final values of the variables used in the benchmark:\n");
  printf ("\n");
  printf ("Int_Glob:            ", Int_Glob); printhex(Int_Glob);
  //printf ("        should be:   %d\n", 5);
  
  printf ("Bool_Glob:           ", Bool_Glob);  printhex(Bool_Glob);
  //printf ("        should be:   %d", 1);
  printf ("Ch_1_Glob:           ", Ch_1_Glob); printhex(Ch_1_Glob);
  //printf ("        should be:   %c", 'A');
  printf ("Ch_2_Glob:           ", Ch_2_Glob); printhex(Ch_2_Glob);
  //printf ("        should be:   %c", 'B');
  printf ("Arr_1_Glob[8]:       ", Arr_1_Glob[8]); printhex(Arr_1_Glob[8]);
  //printf ("        should be:   %d", 7);
  printf ("Arr_2_Glob[8][7]:    ", Arr_2_Glob[8][7]); printhex(Arr_2_Glob[8][7]);
  //printf ("        should be:   Number_Of_Runs + 10");
  printf ("Ptr_Glob->");
  printf ("Ptr_Comp:          "); printhex((uint32_t) Ptr_Glob->Ptr_Comp);
  //printf ("        should be:   (implementation-dependent)");
  printf ("  Discr:             ", Ptr_Glob->Discr); printhex(Ptr_Glob->Discr);
  //printf ("        should be:   %d", 0);
  printf ("  Enum_Comp:         ", Ptr_Glob->variant.var_1.Enum_Comp); printhex(Ptr_Glob->variant.var_1.Enum_Comp);
  //printf ("        should be:   %d", 2);
  printf ("  Int_Comp:          ", Ptr_Glob->variant.var_1.Int_Comp); printhex(Ptr_Glob->variant.var_1.Int_Comp);
  //printf ("        should be:   %d", 17);
  printf ("  Str_Comp:          ", Ptr_Glob->variant.var_1.Str_Comp); printf(Ptr_Glob->variant.var_1.Str_Comp);  printf("\n");
  //printf ("        should be:   DHRYSTONE PROGRAM, SOME STRING");
  printf ("Next_Ptr_Glob->");
  printf ("Ptr_Comp:          "); printhex((uint32_t) Next_Ptr_Glob->Ptr_Comp);
  //printf ("        should be:   (implementation-dependent), same as above");
  printf ("  Discr:             "); printhex(Next_Ptr_Glob->Discr);
  //printf ("        should be:   %d", 0);
  printf ("  Enum_Comp:         "); printhex(Next_Ptr_Glob->variant.var_1.Enum_Comp);
  //printf ("        should be:   %d", 1);
  printf ("  Int_Comp:          "); printhex(Next_Ptr_Glob->variant.var_1.Int_Comp);
  //printf ("        should be:   %d", 18);
  printf ("  Str_Comp:          "); printf(Next_Ptr_Glob->variant.var_1.Str_Comp);  printf("\n");
  printf ("        should be:   DHRYSTONE PROGRAM, SOME STRING\n");
  printf ("Int_1_Loc:           ", Int_1_Loc); printhex(Int_1_Loc);
  //printf ("        should be:   %d", 5);
  printf ("Int_2_Loc:           ", Int_2_Loc); printhex(Int_2_Loc);
  //printf ("        should be:   %d", 13);
  printf ("Int_3_Loc:           ", Int_3_Loc); printhex(Int_3_Loc);
  //printf ("        should be:   %d", 7);
  printf ("Enum_Loc:            ", Enum_Loc); printhex(Enum_Loc);
  //printf ("        should be:   %d", 1);
  printf ("Str_1_Loc:           ", Str_1_Loc); printf(Str_1_Loc); printf("\n");
  printf ("        should be:   DHRYSTONE PROGRAM, 1'ST STRING\n");
  printf ("Str_2_Loc:           ", Str_2_Loc); printf(Str_2_Loc); printf("\n");
  printf ("        should be:   DHRYSTONE PROGRAM, 2'ND STRING\n");
  
  uint32_t instrs = execdEnd - execdBegin;
  uint32_t cycles = End_Time - Begin_Time;
  printf("\n\nRESULTS\n");
  printf("Runtime (cycles) "); printdecu(cycles);
  printf("Executed (instrs) "); printdecu(instrs);
  uint32_t ipc = (instrs * 1000) / cycles;
  printf("mIPC "); printdecu(ipc);
  
  uint32_t dmips = (Number_Of_Runs * 1000) / ((cycles * 1757) / (1000000));
  printf("mDMIPS/MHz "); printdecu(dmips);
}


Proc_1 (Ptr_Val_Par)
/******************/

REG Rec_Pointer Ptr_Val_Par;
    /* executed once */
{
  REG Rec_Pointer Next_Record = Ptr_Val_Par->Ptr_Comp;  
                                        /* == Ptr_Glob_Next */
  /* Local variable, initialized with Ptr_Val_Par->Ptr_Comp,    */
  /* corresponds to "rename" in Ada, "with" in Pascal           */
  
  structassign (*Ptr_Val_Par->Ptr_Comp, *Ptr_Glob);
  Ptr_Val_Par->variant.var_1.Int_Comp = 5;
  Next_Record->variant.var_1.Int_Comp
        = Ptr_Val_Par->variant.var_1.Int_Comp;
  Next_Record->Ptr_Comp = Ptr_Val_Par->Ptr_Comp;
  Proc_3 (&Next_Record->Ptr_Comp);
    /* Ptr_Val_Par->Ptr_Comp->Ptr_Comp
                        == Ptr_Glob->Ptr_Comp */
  if (Next_Record->Discr == Ident_1)
    /* then, executed */
  {
    Next_Record->variant.var_1.Int_Comp = 6;
    Proc_6 (Ptr_Val_Par->variant.var_1.Enum_Comp,
           &Next_Record->variant.var_1.Enum_Comp);
    Next_Record->Ptr_Comp = Ptr_Glob->Ptr_Comp;
    Proc_7 (Next_Record->variant.var_1.Int_Comp, 10,
           &Next_Record->variant.var_1.Int_Comp);
  }
  else /* not executed */
    structassign (*Ptr_Val_Par, *Ptr_Val_Par->Ptr_Comp);
} /* Proc_1 */


Proc_2 (Int_Par_Ref)
/******************/
    /* executed once */
    /* *Int_Par_Ref == 1, becomes 4 */

One_Fifty   *Int_Par_Ref;
{
  One_Fifty  Int_Loc;  
  Enumeration   Enum_Loc;

  Int_Loc = *Int_Par_Ref + 10;
  do /* executed once */
    if (Ch_1_Glob == 'A')
      /* then, executed */
    {
      Int_Loc -= 1;
      *Int_Par_Ref = Int_Loc - Int_Glob;
      Enum_Loc = Ident_1;
    } /* if */
  while (Enum_Loc != Ident_1); /* true */
} /* Proc_2 */


Proc_3 (Ptr_Ref_Par)
/******************/
    /* executed once */
    /* Ptr_Ref_Par becomes Ptr_Glob */

Rec_Pointer *Ptr_Ref_Par;

{
  if (Ptr_Glob != Null)
    /* then, executed */
    *Ptr_Ref_Par = Ptr_Glob->Ptr_Comp;
  Proc_7 (10, Int_Glob, &Ptr_Glob->variant.var_1.Int_Comp);
} /* Proc_3 */


Proc_4 () /* without parameters */
/*******/
    /* executed once */
{
  Boolean Bool_Loc;

  Bool_Loc = Ch_1_Glob == 'A';
  Bool_Glob = Bool_Loc | Bool_Glob;
  Ch_2_Glob = 'B';
} /* Proc_4 */


Proc_5 () /* without parameters */
/*******/
    /* executed once */
{
  Ch_1_Glob = 'A';
  Bool_Glob = false;
} /* Proc_5 */

extern  int     Int_Glob;
extern  char    Ch_1_Glob;


Proc_6 (Enum_Val_Par, Enum_Ref_Par)
/*********************************/
    /* executed once */
    /* Enum_Val_Par == Ident_3, Enum_Ref_Par becomes Ident_2 */

Enumeration  Enum_Val_Par;
Enumeration *Enum_Ref_Par;
{
  *Enum_Ref_Par = Enum_Val_Par;
  if (! Func_3 (Enum_Val_Par))
    /* then, not executed */
    *Enum_Ref_Par = Ident_4;
  switch (Enum_Val_Par)
  {
    case Ident_1:
      *Enum_Ref_Par = Ident_1;
      break;
    case Ident_2:
      if (Int_Glob > 100)
        /* then */
      *Enum_Ref_Par = Ident_1;
      else *Enum_Ref_Par = Ident_4;
      break;
    case Ident_3: /* executed */
      *Enum_Ref_Par = Ident_2;
      break;
    case Ident_4: break;
    case Ident_5:
      *Enum_Ref_Par = Ident_3;
      break;
  } /* switch */
} /* Proc_6 */


Proc_7 (Int_1_Par_Val, Int_2_Par_Val, Int_Par_Ref)
/**********************************************/
    /* executed three times                                      */
    /* first call:      Int_1_Par_Val == 2, Int_2_Par_Val == 3,  */
    /*                  Int_Par_Ref becomes 7                    */
    /* second call:     Int_1_Par_Val == 10, Int_2_Par_Val == 5, */
    /*                  Int_Par_Ref becomes 17                   */
    /* third call:      Int_1_Par_Val == 6, Int_2_Par_Val == 10, */
    /*                  Int_Par_Ref becomes 18                   */
One_Fifty       Int_1_Par_Val;
One_Fifty       Int_2_Par_Val;
One_Fifty      *Int_Par_Ref;
{
  One_Fifty Int_Loc;

  Int_Loc = Int_1_Par_Val + 2;
  *Int_Par_Ref = Int_2_Par_Val + Int_Loc;
} /* Proc_7 */


Proc_8 (Arr_1_Par_Ref, Arr_2_Par_Ref, Int_1_Par_Val, Int_2_Par_Val)
/*********************************************************************/
    /* executed once      */
    /* Int_Par_Val_1 == 3 */
    /* Int_Par_Val_2 == 7 */
Arr_1_Dim       Arr_1_Par_Ref;
Arr_2_Dim       Arr_2_Par_Ref;
int             Int_1_Par_Val;
int             Int_2_Par_Val;
{
  REG One_Fifty Int_Index;
  REG One_Fifty Int_Loc;

  Int_Loc = Int_1_Par_Val + 5;
  Arr_1_Par_Ref [Int_Loc] = Int_2_Par_Val;
  Arr_1_Par_Ref [Int_Loc+1] = Arr_1_Par_Ref [Int_Loc];
  Arr_1_Par_Ref [Int_Loc+30] = Int_Loc;
  for (Int_Index = Int_Loc; Int_Index <= Int_Loc+1; ++Int_Index)
    Arr_2_Par_Ref [Int_Loc] [Int_Index] = Int_Loc;
  Arr_2_Par_Ref [Int_Loc] [Int_Loc-1] += 1;
  Arr_2_Par_Ref [Int_Loc+20] [Int_Loc] = Arr_1_Par_Ref [Int_Loc];
  Int_Glob = 5;
} /* Proc_8 */


Enumeration Func_1 (Ch_1_Par_Val, Ch_2_Par_Val)
/*************************************************/
    /* executed three times                                         */
    /* first call:      Ch_1_Par_Val == 'H', Ch_2_Par_Val == 'R'    */
    /* second call:     Ch_1_Par_Val == 'A', Ch_2_Par_Val == 'C'    */
    /* third call:      Ch_1_Par_Val == 'B', Ch_2_Par_Val == 'C'    */

Capital_Letter   Ch_1_Par_Val;
Capital_Letter   Ch_2_Par_Val;
{
  Capital_Letter        Ch_1_Loc;
  Capital_Letter        Ch_2_Loc;

  Ch_1_Loc = Ch_1_Par_Val;
  Ch_2_Loc = Ch_1_Loc;
  if (Ch_2_Loc != Ch_2_Par_Val)
    /* then, executed */
    return (Ident_1);
  else  /* not executed */
  {
    Ch_1_Glob = Ch_1_Loc;
    return (Ident_2);
   }
} /* Func_1 */


Boolean Func_2 (Str_1_Par_Ref, Str_2_Par_Ref)
/*************************************************/
    /* executed once */
    /* Str_1_Par_Ref == "DHRYSTONE PROGRAM, 1'ST STRING" */
    /* Str_2_Par_Ref == "DHRYSTONE PROGRAM, 2'ND STRING" */

Str_30  Str_1_Par_Ref;
Str_30  Str_2_Par_Ref;
{
  REG One_Thirty        Int_Loc;
      Capital_Letter    Ch_Loc;

  Int_Loc = 2;
  while (Int_Loc <= 2) /* loop body executed once */
    if (Func_1 (Str_1_Par_Ref[Int_Loc],
                Str_2_Par_Ref[Int_Loc+1]) == Ident_1)
    {
      Ch_Loc = 'A';
      Int_Loc += 1;
    }
  if (Ch_Loc >= 'W' && Ch_Loc < 'Z')
    Int_Loc = 7;
  if (Ch_Loc == 'R')
    return (true);
  else
  {
    if (strcmp (Str_1_Par_Ref, Str_2_Par_Ref) > 0)
    {
      Int_Loc += 7;
      Int_Glob = Int_Loc;
      return (true);
    }
    else
      return (false);
  }
}


Boolean Func_3 (Enum_Par_Val)
/***************************/
    /* executed once        */
    /* Enum_Par_Val == Ident_3 */
Enumeration Enum_Par_Val;
{
  Enumeration Enum_Loc;

  Enum_Loc = Enum_Par_Val;
  if (Enum_Loc == Ident_3)
    /* then, executed */
    return (true);
  else /* not executed */
    return (false);
} /* Func_3 */


        /* Procedure for the assignment of structures,          */
        /* if the C compiler doesn't support this feature       */
#ifdef  NOSTRUCTASSIGN
memcpy (d, s, l)
register char   *d;
register char   *s;
register int    l;
{
        while (l--) *d++ = *s++;
}
#endif


