/*	Definition section */
%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

extern int yylineno;
extern int yylex();
extern char* yytext;   // Get current token from lex
extern char buf[256];  // Get current code line from lex

int sem_err_flag = -1;
int syn_err_flag = 0;
char error_id[50];
int scope_num = 0;
int islastzero = 0;
int isfunc = 0;
int printfunc = 0;

char constants[50] = "NULL";
char last_type[10] = "NULL";
char left_var[20] = "NULL";

FILE *file; // To generate .j file for Jasmin

struct symbols{
    int index;
    char value[50];
    char name[50];
    char kind[50];
    char type[50];
    int scope;
    char attribute[50];
    int printed;
    int symbol_num;
    int defined;

    struct symbols *next;
};

struct functions{
    int index;
    char name[50];
    char type[50];
    char attribute[50];

    struct functions *next;
};

struct id_data{
    char id[50];
    char value[100];
} id_struct;

struct func_data{
    char id[50];
    char type[10];
} func_struct;

struct type_node{
    char type[10];

    struct type_node* next;
    struct type_node* prev;
};

struct symbols table[20];
struct functions *func_table;
struct type_node *type_stack;

void yyerror(char *s);

/* Symbol table function - you can add new function if needed. */
int lookup_symbol(char *id, int scope, int mode);
void create_symbol();
void push_stack(char* type);
void pop_stack(char* type);
void insert_symbol(char *name, char *kind, char *type, int scope, char *attribute, char *value);
void insert_function(char* name, char* type, char* attribute);
void dump_symbol(int scope);
void semantic_errors(int kind_of_error, int offset);    // print semantic errors messages
void delete_parameter_symbol(int scope);                // delete the parameter of forwarding function
void fill_parameter(int scope, char *id, char *attribute);  // refill the parameters to forwarding functions
void free_symbol_table();
void search_type(char* id, int scope, char* result);
int search_index(char* id, int scope);
void analyze_parameters(char* attribute);
/* generate jasmin code */
void gencode_function(char* input);
char* casting(char* value, int type);
int j_load_var(char* id);
void j_store_var(char* id, int index, char* type, int scope);
int j_add_expr(char* left_type, char* right_type, char* operation);
int j_mul_expr(char* left_type, char* right_type, char* operation);
void j_assign(char* id, char* left_type, char* right_type);
void j_global_var_declaration(char* id, char* value, char* constant_type);
void j_local_var_declaration(char* id, char* value, char* constant_type);
void j_func_declaration(char* id, char* return_type, char* parameters);
void j_func_call(char* id);
void j_print(char* item, char *type);

%}
/* Use variable or self-defined structure to represent
 * nonterminal and token type
 */
%union {
    int i_val;
    double f_val;
    char* string;
    _Bool b_val;
}

/* Token without return */
%token ADD SUB MUL DIV MOD INC DEC                  // Arithmetic
%token MT LT MTE LTE EQ NE                          // Relational
%token ASGN ADDASGN SUBASGN MULASGN DIVASGN MODASGN // Assignment
%token AND OR NOT                                   // Logical
%token LB RB LCB RCB LSB RSB COMMA                  // Delimiters
%token IF ELSE FOR WHILE BREAK CONT PRINT           // Conditions and loops
%token RET QUOTA                                    // boolean
%token ID SEMICOLON C_COMMENT CPLUS_COMMENT

/* Token with return, which need to sepcify type */
%token <i_val> I_CONST
%token <f_val> F_CONST
%token <string> STR_CONST;
%token <string> STRING INT FLOAT BOOL VOID 
%token <b_val> TRUE FALSE

/* Nonterminal with return, which need to sepcify type */
// %type <f_val> stat compound_statement expression_statement initializer print_func
%type <string> type_specifier declaration_specifiers direct_declarator declarator func_declarator declaration init_declarator_list init_declarator initializer
%type <string> function_definition parameter_list parameter_declaration assignment_operator selection_statement
%type <string> postfix_expression primary_expression unary_expression multiplicative_expression
%type <string> additive_expression relational_expression equality_expression  and_expression inclusive_or_expression exclusive_or_expression
%type <string> logical_and_expression logical_or_expression conditional_expression assignment_expression jump_statement
%type <string> initializer_list id_stat print_statement statement argument_expression_list expression_statement expression
/* Yacc will start at this nonterminal */
%start translation_unit

/* Grammar section */
%%
translation_unit
    : external_declaration
    | translation_unit external_declaration
    ;

external_declaration
    : function_definition
    | declaration
    ;

function_definition
    : declaration_specifiers declarator declaration_list compound_statement
    /* normal function declaration and definition */
    | declaration_specifiers func_declarator    {   /* split the string that contains ID and parameter list */
                                                    char *temp;
                                                    // printf("$2 %s\n", $2);
                                                    temp = strtok($2, ":");
                                                    /* ID */
                                                    $2 = temp;
                                                    // printf("%s\n", $2);
                                                    /* parameters */
                                                    temp = strtok(NULL, ":");
                                                    /* lookup */
                                                    int result = lookup_symbol($2, scope_num, 1);
                                                    /* if return 2, it is a forwarding function(encountered at the 2nd time) */
                                                    if(result == 2){
                                                        /* refill the attribute with the ID and parameter list */
                                                        fill_parameter(scope_num, $2, temp);
                                                    }
                                                    /* if return 1, redeclared function*/
                                                    else if(result){
                                                        // redeclared function
                                                        /* set semantic error flag and lex will call the semantic function */
                                                        sem_err_flag = 1;
                                                        /* save the ID to use in semantic function */
                                                        strcpy(error_id, $2);
                                                    }
                                                    /* return 0, new function, insert the symbol */
                                                    else {
                                                        char tmp[20];
                                                        if(temp == NULL)                                                        {
                                                            strcpy(tmp, "NULL");
                                                        }
                                                        else strcpy(tmp, temp);
                                                        strcpy(func_struct.id, $2);
                                                        strcpy(func_struct.type, $1);
                                                        j_func_declaration($2, $1, tmp);
                                                        insert_symbol($2, "function", $1, scope_num, tmp, "NULL");
                                                        insert_function($2, $1, tmp);
                                                    }    
                                                } compound_statement {  // printf("%s\n", func_struct.type);
                                                                        if(!strcmp(func_struct.type, "I"))
                                                                            fprintf(file, "\tireturn\n.end method\n");
                                                                        else if(!strcmp(func_struct.type, "F"))
                                                                            fprintf(file, "\tfreturn\n.end method\n");
                                                                        else if(!strcmp(func_struct.type, "V"))
                                                                            fprintf(file, "\treturn\n.end method\n");
                                                                        strcpy(func_struct.id, "");
                                                                        strcpy(func_struct.type, "");
                                                                    }
    | declarator declaration_list compound_statement
    | declarator compound_statement
    | declaration_specifiers func_declarator SEMICOLON   {   /* forwarding function(encountered at the first time) */
                                                        char *temp;
                                                        temp = strtok($2, ":");
                                                        $2 = temp;
                                                        char notdef[15];
                                                        strcpy(notdef, "notdefined");
                                                        /* check if redeclared */
                                                        if(lookup_symbol($2, scope_num, 1)){
                                                            // redeclared function
                                                            sem_err_flag = 1;
                                                            strcpy(error_id, $2);
                                                        }
                                                        /* false, insert */
                                                        else{
                                                            insert_symbol($2, "function", $1, scope_num, notdef, "NULL");
                                                            insert_function($2, $1, "NULL");
                                                        }
                                                        /* delete the symbols of the forwarding function */
                                                        delete_parameter_symbol(scope_num+1);
                                                    }
    ;

declaration_specifiers
    : type_specifier    { $$ = $1; }
    | type_specifier declaration_specifiers { ; }
    ;

declaration_list
    : declaration
    | declaration_list declaration
    ;

block_item_list
	: block_item
	| block_item_list block_item
    ;

block_item
	: declaration_list
	| statement
	;

declarator
    : direct_declarator
    ;
func_declarator
    : direct_declarator
    ;

direct_declarator
    : ID                { $$ = strdup(yytext); /*printf("dir %s\n", yytext);*/ }
    | LB declarator RB  { ; }
    | direct_declarator LSB conditional_expression RSB
    | direct_declarator LSB RSB
    /* attach parameters together */
    | direct_declarator LB{ scope_num++; } parameter_list RB { scope_num--; strcat($$, ":"); strcat($$, $4); }
    | direct_declarator LB{ scope_num++; } identifier_list RB{ scope_num--; }
    | direct_declarator LB RB  
    ;

declaration
    : declaration_specifiers SEMICOLON
    | declaration_specifiers init_declarator_list SEMICOLON     {   /* variable declaration */
                                                                    int result = lookup_symbol($2, scope_num, 0);
                                                                    // printf("decl %s\n", $2);
                                                                    // printf("declaration %s %s %d\n", $1, $2, scope_num);
                                                                    if(result){
                                                                        // redeclared variable
                                                                        sem_err_flag = 0;
                                                                        strcpy(error_id, $2);
                                                                    }
                                                                    else{
                                                                        insert_symbol($2, "variable", $1, scope_num, "NULL", constants);
                                                                        /* global variable declaration */
                                                                        if(scope_num == 0){
                                                                            // printf("global variable\n");
                                                                            // generate code
                                                                            j_global_var_declaration($2, constants, $1);
                                                                        }
                                                                        /* local variable declaration */
                                                                        else{
                                                                            // printf("local variable\n");
                                                                            //printf("decl id_struct %s %s %s\n", $1, id_struct.id, id_struct.value);
                                                                            
                                                                            j_local_var_declaration($2, id_struct.value, $1);
                                                                            j_assign($2, $1, id_struct.value);
                                                                        }
                                                                        strcpy(constants, "NULL");
                                                                    }
                                                                }
    | id_stat ASGN assignment_expression SEMICOLON  {   //printf("here %s %s %d\n", $1, $3, isfunc);
                                                        // printf("%s\n", id_struct.id);
                                                        char type[20];
                                                        char out_str[200];
                                                        search_type($1, scope_num, type);
                                                        int index = search_index($1, scope_num);
                                                        if(!isfunc){                    
                                                            if(!strcmp(type, "I") && !strcmp($3, "I"))
                                                                j_store_var($1, index, type, scope_num);
                                                            else if(!strcmp(type, "F") && !strcmp($3, "F"))
                                                                j_store_var($1, index, type, scope_num);
                                                            else if(!strcmp(type, "F") && !strcmp($3, "I")){
                                                                gencode_function("\ti2f\n");
                                                                j_store_var($1, index, type, scope_num);
                                                            }
                                                            else if(!strcmp(type, "I") && !strcmp($3, "F")){
                                                                gencode_function("\tf2i\n");
                                                                j_store_var($1, index, type, scope_num);
                                                            }
                                                        }
                                                        else{
                                                            if(!strcmp(type, "I") && !strcmp(func_struct.type, "I"))
                                                                j_store_var($1, index, type, scope_num);
                                                            else if(!strcmp(type, "F") && !strcmp(func_struct.type, "F"))
                                                                j_store_var($1, index, type, scope_num);
                                                            else if(!strcmp(type, "F") && !strcmp(func_struct.type, "I")){
                                                                gencode_function("\ti2f\n");
                                                                j_store_var($1, index, type, scope_num);
                                                            }
                                                            else if(!strcmp(type, "I") && !strcmp(func_struct.type, "F")){
                                                                gencode_function("\tf2i\n");
                                                                j_store_var($1, index, type, scope_num);
                                                            }
                                                        }
                                                    }
    | id_stat postfix_expression SEMICOLON  {   
                                                j_func_call(func_struct.id);                               
                                            }
    ;

identifier_list
    : ID
    | identifier_list COMMA ID
    ;

init_declarator_list
    : init_declarator                               {   $$ = $1; 
                                                        // printf("init_decl_list %s\n", $$);
                                                        // printf("id_struct %s %s\n", id_struct.id, id_struct.value); 
                                                    }
    | init_declarator_list COMMA init_declarator
    ;

/* statements */
statement
    : compound_statement    {;}
    | expression_statement  {;}
    | selection_statement   {;}
    | iteration_statement   {;}
    | jump_statement        {;}
    | print_statement       {;}
    ;

compound_statement
    : LCB RCB
    | LCB{ scope_num++; } block_item_list RCB{ scope_num--; }
    ;

expression_statement
    : COMMA {}
    | expression SEMICOLON  { $$ = $1; /*printf("expr stmt %s %s\n", $1, left_var);*/ }
    ;

selection_statement
    : IF LB expression RB statement     { /*printf("select %s\n", $3);*/ }
    | IF LB expression RB statement ELSE statement  {}
    ;

iteration_statement
    : WHILE LB expression RB statement
    | FOR LB expression_statement expression_statement RB statement
    | FOR LB expression_statement expression_statement expression RB statement
    ;

jump_statement
    : CONT SEMICOLON    {}
    | BREAK SEMICOLON   {}
    | RET SEMICOLON     {}
    | RET expression SEMICOLON  {   // printf("%s %s\n", $2, func_struct.type); 
                                    char temp[50];
                                    strcpy(temp, strdup($2));
                                    if(!strcmp(func_struct.type, "I") && !strcmp(temp, "I")){
                                    }
                                    else if(!strcmp(func_struct.type, "F") && !strcmp(temp, "F")){
                                    }
                                    else if(!strcmp(func_struct.type, "I") && !strcmp(temp, "F")){
                                        gencode_function("\tf2i\n");
                                    }
                                    else if(!strcmp(func_struct.type, "F") && !strcmp(temp, "I")){
                                        gencode_function("\tif2f\n");
                                    }
                                }
    ;

print_statement
    : PRINT LB id_stat RB SEMICOLON                 {   if($3 != NULL){                 // if variable undeclared, do nothing
                                                            char type[10];
                                                            search_type(strdup($3), scope_num, type);
                                                            // printf("%s %s %d\n", $3, type, scope_num);
                                                            j_print($3, type);
                                                        }                                                        
                                                    }
    | PRINT LB QUOTA STR_CONST{ strcpy(constants, strdup(yytext)); } QUOTA RB SEMICOLON{
                                                        // printf("print %s %s %d\n", constants, "string", scope_num);
                                                        char temp[50];
                                                        sprintf(temp, "\"%s\"", constants);
                                                        j_print(temp, "string");
                                                        strcpy(constants, "NULL");
                                                    }
    | PRINT LB I_CONST{ strcpy(constants, strdup(yytext)); } RB SEMICOLON{
                                                        // printf("print %s %s %d\n", constants, "int", scope_num);
                                                        j_print(constants, "int");
                                                        strcpy(constants, "NULL");
                                                    }
    | PRINT LB F_CONST{ strcpy(constants, strdup(yytext));} RB SEMICOLON{
                                                        // printf("print %s %s %d\n", constants, "float", scope_num);
                                                        j_print(constants, "float");
                                                        strcpy(constants, "NULL");
                                                    }
    ;

conditional_expression
    : logical_or_expression { $$ = $1; /*printf("condi %s\n", $$);*/ }
    ;

parameter_list
    : parameter_declaration { $$ = $1; }
    /* attach parameters */
    | parameter_list COMMA parameter_declaration    { $$ = strcat($1, ", "); $$ = strcat($$, $3); }
    ;

init_declarator
    : declarator                    {   $$ = $1; 
                                        // printf("init_declarator %s\n", $1);
                                        strcpy(id_struct.id, $1);
                                        strcpy(id_struct.value, "NULL");
                                    }
    | func_declarator               { $$ = $1; }
    | declarator ASGN initializer   {   char temp[100];
                                        strcpy(temp, strdup($3));
                                        char c = temp[0];
                                        // asign to one item
                                        $$ = $1; 
                                        // printf("init_declarator ASGN %s %s\n", $1, $3);
                                        strcpy(id_struct.id, $1);
                                        strcpy(id_struct.value, $3);
                                    }
    ;

id_stat
    : ID    {   // printf("id_stat %s\n", yytext);
                if(!lookup_symbol(yytext, scope_num, 1)){
                    sem_err_flag = 2;
                    strcpy(error_id, yytext);
                }
                else{
                    $$ = strdup(yytext);
                }
            }
    ;

logical_or_expression
    : logical_and_expression    { $$ = $1; /*printf("logi or %s\n", $$);*/ }
    | logical_or_expression OR logical_and_expression
    ;

expression
    : assignment_expression     { $$ = $1; /*printf("expr %s\n", $1);*/ }
    | expression COMMA assignment_expression
    ;

parameter_declaration
    : declaration_specifiers declarator {   /* check parameter*/
                                            if(!lookup_symbol($2, scope_num, 0))
                                                insert_symbol($2, "parameter", $1, scope_num, "NULL", "NULL");
                                            $$ = $1; 
                                        }
    | declaration_specifiers
    ;

initializer
    : assignment_expression             { $$ = $1; /*printf("initializer %s\n", $$);*/ }
    | LCB initializer_list RCB          {;}
    | LCB initializer_list COMMA RCB    {;}
    ;

logical_and_expression
    : inclusive_or_expression   { $$ = $1; /*printf("logic and %s\n", $$);*/ }
    | logical_and_expression AND inclusive_or_expression
    ;

assignment_expression
    : conditional_expression    { $$ = $1; /*printf("con %s\n", $$);*/ }
    | unary_expression assignment_operator assignment_expression   { /*printf("ass %s %s\n", $1, $3);*/ }
    ;

initializer_list
    : initializer
    | initializer_list SEMICOLON initializer
    ;

inclusive_or_expression
    : exclusive_or_expression   { $$ = $1; /*printf("incl %s\n", $$);*/ }
    ;

unary_expression
    : postfix_expression        {   $$ = $1;
                                    // printf("unary %s %s\n", func_struct.id, func_struct.type);
                                    if(printfunc){
                                        j_func_call(func_struct.id);
                                        printfunc = 0;
                                    }
                                }
    | INC unary_expression      {}
    | DEC unary_expression      {}
    | unary_operator unary_expression   {}
    ;

assignment_operator
    : ASGN      {   char temp[10];
                    strcpy(temp, "A");
                    $$ = temp;
                }
    | ADDASGN   {   char temp[10];
                    strcpy(temp, "AA");
                    $$ = temp;
                }
    | SUBASGN   {   char temp[10];
                    strcpy(temp, "SA");
                    $$ = temp;
                }
    | MULASGN   {   char temp[10];
                    strcpy(temp, "MA");
                    $$ = temp;
                }
    | DIVASGN   {   char temp[10];
                    strcpy(temp, "DA");
                    $$ = temp;
                }
    | MODASGN   {   char temp[10];
                    strcpy(temp, "MDA");
                    $$ = temp;
                }
    ;

exclusive_or_expression
    : and_expression            { $$ = $1; /*printf("excl %s\n", $$);*/ }
    ;

postfix_expression
    : primary_expression        {   /* check ID declared or not */
                                    if($1 != NULL) {
                                        // printf("post %s\n", $1);
                                        char temp[50];
                                        strcpy(temp, $1);
                                        int len = strlen(temp);
                                        /* passing constants end with '/' */
                                        if(temp[len-1] == '/'){
                                            temp[len-1] = '\0';
                                            $$ = temp;
                                            len = strlen(constants);
                                        }
                                        else if(!strcmp($1, "I") || !strcmp($1, "F") || !strcmp($1, "S")){
                                            // printf("in postfix\n");
                                        }
                                        else if(!lookup_symbol($1, scope_num, 1)){
                                            // printf("here?\n");
                                            // undeclared variable
                                            sem_err_flag = 2;
                                            strcpy(error_id, $1);

                                        }
                                    }                    
                                }
    | postfix_expression LSB expression RSB
    | postfix_expression LB RB                          {   /* check function name declared or not */
                                                            if($1 != NULL) {
                                                                // printf("her %s %s\n", func_struct.id, func_struct.type);
                                                                if(!lookup_symbol(func_struct.id, scope_num, 3)){
                                                                    // undeclared function
                                                                    sem_err_flag = 3;
                                                                    strcpy(error_id, $1);
                                                                }
                                                            }
                                                        }
    | postfix_expression LB argument_expression_list RB {   /* check function name declared or not */
                                                            if($1 != NULL) {
                                                                // printf("here %s %s\n", $1, $3);
                                                                // printf("her %s %s\n", func_struct.id, func_struct.type);
                                                                if(!lookup_symbol(func_struct.id, scope_num, 3)){
                                                                    // undeclared function
                                                                    sem_err_flag = 3;
                                                                    strcpy(error_id, $1);
                                                                }

                                                            }
                                                            if($3 != NULL){
                                                                // printf("post %s\n", $3);
                                                            }
                                                            printfunc = 1;
                                                        }
    | postfix_expression INC
    | postfix_expression DEC
    ;

unary_operator
    : ADD
    | SUB
    | NOT
    ;

and_expression
    : equality_expression       { $$ = $1; /*printf("and %s\n", $$);*/ }
    ;

primary_expression
    : ID                        {   
                                    // printf("primary %s\n", yytext);
                                    if(!lookup_symbol(yytext, scope_num, 1)){
                                        // undeclared variable
                                        sem_err_flag = 2;
                                        strcpy(error_id, yytext);
                                    }
                                    if(!isfunc){
                                        int type = j_load_var(yytext);
                                        // printf("type %d\n", type);
                                        char temp[10];
                                        if(type == 0) strcpy(temp, "I");
                                        else if(type == 1) strcpy(temp, "F");
                                        else if(type == 2) strcpy(temp, "S");
                                        else if(type == 3) strcpy(temp, "B");
                                        $$ = temp;
                                        strcpy(left_var, yytext);
                                    }
                                    else {
                                        
                                        $$ = strdup(yytext);
                                    }
                                }
    | I_CONST                   {   strcpy(constants, strdup(yytext));
                                    // printf("I CON %s\n", constants);
                                    char temp[50];
                                    if(scope_num > 0){
                                        sprintf(temp, "\tldc %s\n", strdup(yytext));
                                        gencode_function(temp);
                                        strcpy(temp, "I");
                                        int num;
                                        sscanf(yytext, "%d", &num);
                                        if(num == 0)    islastzero = 1;
                                        else islastzero = 0;
                                    }
                                    else{
                                        sprintf(temp, "%s/", strdup(yytext));
                                    }
                                    $$ = temp;
                                    
                                }
    | F_CONST                   {   strcpy(constants, strdup(yytext));
                                    //printf("%s\n", constants);
                                    char temp[50];
                                    if(scope_num > 0){
                                        sprintf(temp, "\tldc %s\n", strdup(yytext));
                                        gencode_function(temp);
                                        strcpy(temp, "F");
                                        float num;
                                        sscanf(yytext, "%f", &num);
                                        if(num == 0)    islastzero = 1;
                                        else islastzero = 0;
                                    }
                                    else{
                                        sprintf(temp, "%s/", strdup(yytext));
                                    }
                                    $$ = temp;
                                }
    | QUOTA STR_CONST{  sprintf(constants, "%s/", strdup(yytext));                        
                    }   QUOTA   {   
                                    $$ = constants;
                                    char temp[50];
                                    if(scope_num > 0){
                                        sprintf(temp, "\tldc \"%s\"\n", constants);
                                        gencode_function(temp);
                                        strcpy(temp, "S");
                                    }
                                    else{
                                        sprintf(temp, "%s", constants);
                                    }
                                    $$ = temp;
                                }
    | TRUE                      {   strcpy(constants, "true/");
                                    char temp[50];
                                    if(scope_num > 0){
                                        sprintf(temp, "\tldc 1\n");
                                        gencode_function(temp);
                                        strcpy(temp, "B");
                                    }
                                    else{
                                        sprintf(temp, "%s/", strdup(yytext));
                                    }
                                    $$ = temp;
                                }
    | FALSE                     {   strcpy(constants, "false/");
                                    char temp[50];
                                    if(scope_num > 0){
                                        sprintf(temp, "\tldc 0\n");
                                        gencode_function(temp);
                                        strcpy(temp, "B");
                                    }
                                    else{
                                        sprintf(temp, "%s/", strdup(yytext));
                                    }
                                    $$ = temp;
                                }
    | LB expression RB  {}   
    ;

argument_expression_list
    : assignment_expression {   // printf("ass argu %s\n", $1);
                                $$ = $1;    
                            }
    | argument_expression_list COMMA assignment_expression  {   // printf("argu 2 %s %s\n", $1, $3);
                                                                $$ = $1;
                                                                strcat($$, ":");
                                                                strcat($$, strdup($3));
                                                                // printf("argu 2 %s\n", $$);
                                                            }
    ;

equality_expression
    : relational_expression                             { $$ = $1; /*printf("equal rel %s\n", $$);*/ }
    | equality_expression EQ relational_expression      { /*printf("== %s %s\n", $1, $3);*/ }
    | equality_expression NE relational_expression      { /*printf("!= %s %s\n", $1, $3);*/ }
    ;

relational_expression
    : additive_expression                               { $$ = $1; /*printf("rel %s\n", $$);*/ }
    | relational_expression LT additive_expression      { /*printf("< %s %s\n", $1, $3);*/ }
    | relational_expression MT additive_expression      { /*printf("> %s %s\n", $1, $3);*/ }
    | relational_expression LTE additive_expression     { /*printf("<= %s %s\n", $1, $3);*/ }
    | relational_expression MTE additive_expression     { /*printf(">= %s %s\n", $1, $3);*/ }
    ;

additive_expression
    : multiplicative_expression                         { $$ = $1; /*printf("add %s\n", $$);*/ strcpy(last_type, $1); push_stack($1); }
    | additive_expression ADD multiplicative_expression {   // printf("here add %s %s\n", last_type, $3);
                                                            char tmp[10];
                                                            pop_stack(tmp);
                                                            // printf("pop stack add %s\n", tmp);
                                                            int type = j_add_expr(tmp, $3, "ADD");
                                                            
                                                            char temp[10];
                                                            if(!type) strcpy(temp, "I");
                                                            else if(type) strcpy(temp, "F");
                                                            $$ = temp;
                                                            // printf("add type %s\n", $$);
                                                        }
    | additive_expression SUB multiplicative_expression {   // printf("here sub %s %s\n", last_type, $3);
                                                            char tmp[10];
                                                            pop_stack(tmp);
                                                            // printf("pop stack %s %s\n", $1, $3);
                                                            int type = j_add_expr(tmp, $3, "SUB");
                                                            
                                                            char temp[10];
                                                            if(!type) strcpy(temp, "I");
                                                            else if(type) strcpy(temp, "F");
                                                            $$ = temp;
                                                            // printf("sub type %s\n", $$);
                                                        }
    ;

multiplicative_expression
    : unary_expression                                {   $$ = $1; /*printf("mul %s\n", $$);*/ strcpy(last_type, $1); push_stack($1); }
    | multiplicative_expression MUL unary_expression  {   // printf("* %s %s\n", last_type, $3); 
                                                            char tmp[10];
                                                            pop_stack(tmp);
                                                            // printf("pop stack %s\n", tmp);
                                                            int type = j_mul_expr(tmp, $3, "MUL");
                                                            
                                                            char temp[10];
                                                            if(!type) strcpy(temp, "I");
                                                            else if(type) strcpy(temp, "F");
                                                            $$ = temp;
                                                            // printf("mul type %s\n", $$);
                                                        }
    | multiplicative_expression DIV unary_expression  {   // printf("/ %s %s\n", last_type, $3); 
                                                            char tmp[10];
                                                            pop_stack(tmp);
                                                            // printf("pop stack %s\n", tmp);
                                                            int type = j_mul_expr(tmp, $3, "DIV");

                                                            char temp[10];
                                                            if(!type) strcpy(temp, "I");
                                                            else if(type) strcpy(temp, "F");
                                                            $$ = temp;
                                                            // printf("div type %s\n", $$);
                                                        }
    | multiplicative_expression MOD unary_expression  {   // printf("%% %s %s\n", last_type, $3); 
                                                            char tmp[10];
                                                            pop_stack(tmp);
                                                            // printf("pop stack %s\n", tmp);

                                                            int type = j_mul_expr(tmp, $3, "REM");
                                                            char temp[10];
                                                            if(!type) strcpy(temp, "I");
                                                            $$ = temp;
                                                            // printf("rem type %s\n", $$);
                                                        }
    ;

/* actions can be taken when meet the token or rule */
/* types */
type_specifier
    : INT   { $$ = strdup("I"); }
    | FLOAT { $$ = strdup("F"); }
    | BOOL  { $$ = strdup("B"); }
    | STRING { $$ = strdup("S"); }
    | VOID  { $$ = strdup("V"); }
;

%%


/* C code section */
int main(int argc, char** argv)
{
    yylineno = 0;
    
    file = fopen("compiler_hw3.j","w");
    fprintf(file,   ".class public compiler_hw3\n"
                    ".super java/lang/Object\n");
    
    create_symbol();
    yyparse();
    /* if there is a syntax error, don't print the last line */
    if(!syn_err_flag){
        dump_symbol(0);
        printf("\nTotal lines: %d \n",yylineno);
    }

    fclose(file);

    return 0;
}

void yyerror(char *s)
{
    /* check if there is a semantic error first */
    if(sem_err_flag == -1)
        printf("%d: %s\n", yylineno+1, buf);
    else semantic_errors(sem_err_flag, 1);
    
    syn_err_flag = 1;
    printf("\n|-----------------------------------------------|\n");
    printf("| Error found in line %d: %s\n", yylineno+1, buf);
    printf("| %s", s);
    printf("\n|-----------------------------------------------|\n\n");
    exit(-1);
}

/* stmbol table functions */
/* initialize the table */
void create_symbol() {
    int i;
    for(i = 0; i < 20; i++){
        strcpy(table[i].name, "HEAD");
        table[i].next = NULL;
        table[i].scope = 0;
        table[i].printed = -1;
        table[i].symbol_num = 0;
        table[i].defined = -1;
    }
    func_table = (struct functions *)malloc(sizeof(struct functions));
    strcpy(func_table->name, "HEAD");
    strcpy(func_table->type, "NULL");
    strcpy(func_table->attribute, "NULL");
    func_table->index = -1;
    func_table->next = NULL;

    type_stack = (struct type_node *)malloc(sizeof(struct type_node));
    strcpy(type_stack->type, "HEAD");
    type_stack->next = NULL;
    type_stack->prev = NULL;

}

void push_stack(char* type){
    struct type_node *new_type, *temp;
    new_type = (struct type_node *)malloc(sizeof(struct type_node));
    strcpy(new_type->type, type);
    int count = 1;
    temp = type_stack;
    while(temp->next != NULL){
        count++;
        temp = temp->next;
    }
    temp->next = new_type;
    new_type->next = NULL;
    new_type->prev = temp;
    count++;
    // printf("count %d\n", count);
}

void pop_stack(char* type){
    struct type_node *temp;

    temp = type_stack;
    while(temp->next != NULL){
        temp = temp->next;
    }
    strcpy(type, temp->type);
    temp->prev->next = NULL;
    temp->prev = NULL;
    free(temp);
}

/* insert symbols */
void insert_symbol(char *name, char *kind, char *type, int scope, char *attribute, char *value) {
    struct symbols *temp, *new_symbol;

    /* traversal to the last symbol */
    temp = &table[scope];
    while(temp->next != NULL){
        temp = temp->next;
    }
    
    /* setting the new symbol */
    new_symbol = (struct symbols *)malloc(sizeof(struct symbols));
    strcpy(new_symbol->name, name);
    strcpy(new_symbol->kind, kind);
    strcpy(new_symbol->type, type);
    
    if(!strcmp(value, "NULL")) strcpy(new_symbol->value, "\0");
    else    strcpy(new_symbol->value, value);
    
    /* some situations for attribute */
    if(attribute == NULL || !strcmp(attribute, "NULL")){
        // variable
        strcpy(new_symbol->attribute, "\0");
        new_symbol->defined = 1;
    }
    // function forwarding, undefined
    else if(!strcmp(attribute, "notdefined"))   new_symbol->defined = 0;
    else {
        // function defined and parameter
        strcpy(new_symbol->attribute, attribute);
        new_symbol->defined = 1;
    }
    new_symbol->index = table[scope].symbol_num;
    new_symbol->scope = scope;
    new_symbol->printed = -1;
    new_symbol->next = NULL;
    temp->next = new_symbol;
    table[scope].symbol_num++;

}

/* insert new function to function table */
void insert_function(char* name, char* type, char* attribute){
    struct functions *temp, *new_function;
    // printf("%s %s %s\n", name, type, attribute);
    temp = func_table;
    while(temp->next != NULL)
        temp = temp->next;
    
    new_function = (struct functions *)malloc(sizeof(struct functions));
    strcpy(new_function->name, name);

    if(!strcmp(type, "I"))    strcpy(new_function->type, "I");
    else if(!strcmp(type, "F")) strcpy(new_function->type, "F");
    else if(!strcmp(type, "V"))  strcpy(new_function->type, "V");
    
    if(attribute == NULL || !strcmp(attribute, "NULL")) strcpy(new_function->attribute, "V");
    else {
        strcpy(new_function->attribute, attribute);
    }

    // printf("%s\n", attribute);
    new_function->index = temp->index + 1;
    new_function->next = NULL;
    temp->next = new_function;

    // struct functions *temp1;
    // temp1 = func_table;
    // while(temp1 != NULL){
    //     printf("%d %s %s %s\n", temp1->index, temp1->name, temp1->type, temp1->attribute);
    //     temp1 = temp1->next;
    // }
}

/* lookup symbols from scope up to 0 */
int lookup_symbol(char *id, int scope, int mode) {  // mode 0: redeclared variable 1: undeclared variable
                                                    //      2: redeclared function 3: undeclared function
    struct symbols *temp;
    int existed = 0, cur_scope = scope;
    isfunc = 0;
    if(!mode || mode == 2){
        temp = &table[scope];
        if(table[scope].symbol_num == 0){
            existed = 0;
        }
        else {
            while(temp != NULL){
                /* if this is a variable already existed */
                if(!strcmp(temp->name, id)){
                    if(!strcmp(temp->kind, "function")){
                        // printf("is func\n");
                        strcpy(func_struct.id, temp->name);
                        strcpy(func_struct.type, temp->type);
                        isfunc = 1;
                    }
                    else isfunc = 0;
                    existed = 1;
                    break;
                }
                temp = temp->next;
            }
        }
    }
    else if(mode || mode == 3){
        while(scope >= 0){
            temp = &table[scope];
            if(table[scope].symbol_num == 0){
                scope--;
                continue;
            }
            while(temp != NULL){
                if(!strcmp(temp->name, id)){
                    /* if this is a function name and it is undfined */
                    if(!temp->defined) existed = 2;  
                    else existed = 1;
                    if(!strcmp(temp->kind, "function")){
                        // printf("is func\n");
                        strcpy(func_struct.id, temp->name);
                        strcpy(func_struct.type, temp->type);
                        isfunc = 1;
                    }
                    else isfunc = 0;
                    break;
                }
                temp = temp->next;
            }
            scope--;
            if(existed) break;
        }
    }
    // return 0: not exist 1: exist 2: forwarding
    return existed;
}

/* lookup function table to get the id's type and attribute */
void lookup_function(char* id, char* type, char* attribute){
    struct functions *temp;
    temp = func_table;
    while(temp != NULL){
        if(!strcmp(temp->name, id)){
            strcpy(type, temp->type);
            strcpy(attribute, temp->attribute);
            break;
        }
        temp = temp->next;
    }
}

/* dump symbols */
void dump_symbol(int scope) {
    /* if there is not symbol in this scope, return */
    if(table[scope].symbol_num == 0)    return;
    
    printf("\n%-10s%-10s%-12s%-10s%-10s%-10s\n\n",
           "Index", "Name", "Kind", "Type", "Scope", "Attribute");
    
    /* traversal and print */
    int i = 0, index = 0;
    while(table[scope].next != NULL){
        struct symbols *temp = &table[scope];
        temp = temp->next;

        printf("%-10d%-10s%-12s", index++, temp->name, temp->kind);
        if(!strcmp(temp->type, "I"))    printf("%-10s", "int");
        else if(!strcmp(temp->type, "F"))    printf("%-10s", "float");
        else if(!strcmp(temp->type, "V"))    printf("%-10s", "void");
        else if(!strcmp(temp->type, "S"))    printf("%-10s", "string");
        else if(!strcmp(temp->type, "B"))    printf("%-10s", "bool");
        printf("%-10d", temp->scope);
        if(strcmp(temp->attribute, "\0")){
            char str[20];
            strcpy(str, temp->attribute);
            if(!strcmp(str, "[Ljava/lang/String;")) {}
            else {
                // printf("c %s", str);
                int i = 0;
                while(i < strlen(str)){
                    if(str[i] == 'I')    printf("%s", "int");
                    else if(str[i] == 'F')    printf("%s", "float");
                    else if(str[i] == 'V')    printf("%s", "void");
                    else if(str[i] == 'S')    printf("%s", "string");
                    else if(str[i] == 'B')    printf("%s", "bool");
                    i++;
                    if(i < strlen(str))  printf(", ");
                }
                printf("\n");
            }
            // if(!strcmp(temp->type, "I"))    printf("%s\n", "int");
            // else if(!strcmp(temp->type, "F"))    printf("%s\n", "float");
            // else if(!strcmp(temp->type, "V"))    printf("%s\n", "void");
            // else if(!strcmp(temp->type, "S"))    printf("%s\n", "string");
            // else if(!strcmp(temp->type, "B"))    printf("%s\n", "bool");
            // printf("%s\n", temp->attribute);
        }
        else printf("\n");
        /* after printed, delete and free */
        table[scope].next = temp->next;
        free(temp);
        i++;
    }
    printf("\n");
    table[scope].symbol_num = 0;
}

/* semantic error */
void semantic_errors(int kind_of_error, int offset){
    int line = yylineno + offset;
    switch(kind_of_error){
        case 0:                 // redeclared variable
            printf("%d: %s\n", line, buf);
            printf("\n|-----------------------------------------------|\n");
            printf("| Error found in line %d: %s\n", line, buf);
            printf("| Redeclared variable %s", error_id);
            printf("\n|-----------------------------------------------|\n\n");
            break;
        case 1:                 // redeclared function
            printf("%d: %s\n", line, buf);
            printf("\n|-----------------------------------------------|\n");
            printf("| Error found in line %d: %s\n", line, buf);
            printf("| Redeclared function %s", error_id);
            printf("\n|-----------------------------------------------|\n\n");
            break;
        case 2:                 // undeclared variable
            printf("%d: %s\n", line, buf);
            printf("\n|-----------------------------------------------|\n");
            printf("| Error found in line %d: %s\n", line, buf);
            printf("| Undeclared variable %s", error_id);
            printf("\n|-----------------------------------------------|\n\n");
            break;
        case 3:                 // undeclared function
            printf("%d: %s\n", line, buf);
            printf("\n|-----------------------------------------------|\n");
            printf("| Error found in line %d: %s\n", line, buf);
            printf("| Undeclared function %s", error_id);
            printf("\n|-----------------------------------------------|\n\n");
            break;
        default:;
        sem_err_flag = -1;
    }
}

/* delete the parameter */
void delete_parameter_symbol(int scope) {
    /* traversal and delete the symbols of the forwading function */
    while(table[scope].next != NULL){
        struct symbols *temp = &table[scope];
        temp = temp->next;

        table[scope].next = temp->next;
        free(temp);
    }
    table[scope].symbol_num = 0;
}

/* fill the attribute to the undefined function */
void fill_parameter(int scope, char *id, char *attribute) {
    struct symbols *temp = &table[scope];
    temp = temp->next;
    
    while(temp != NULL){
        if(!strcmp(temp->name, id)){
            strcpy(temp->attribute, attribute);
            temp->defined = 1;
            break;
        }
        temp = temp->next;        
    }
}

/* lookup symbol table to find the type of the variable */
void search_type(char* id, int scope, char* result){
    struct symbols *temp;

    int found = 0;
    while(scope >= 0){
        temp = &table[scope];
        if(table[scope].symbol_num > 0){
            while(temp != NULL){
                /* if this is a variable already existed */
                if(!strcmp(temp->name, id)){
                    // printf("find type %s\n", temp->type);
                    strcpy(result, temp->type);
                    found = 1;
                    break;
                }
                temp = temp->next;
            }
        }
        if(found)   break;
        scope--;
    }
}

/* lookup symbol table to find the index of the variable */
int search_index(char* id, int scope){  // return > 0: local; == -1, global
    struct symbols *temp;
    int found = 0, index;

    while(scope > 0){
        temp = &table[scope];
        if(table[scope].symbol_num > 0){
            while(temp != NULL){
                /* if this is a variable already existed */
                if(!strcmp(temp->name, id)){
                    // printf("find index %d\n", temp->index);
                    index = temp->index;
                    found = 1;  // in local
                    break;
                }
                temp = temp->next;
            }
        }
        if(found) break;
        scope--;
    }
    /* variable in global */
    if(!found)  index = -1;
    return index;
}

/* analyze the types of parameters */
void analyze_parameters(char* attribute){
    char temp[50];
    strcpy(temp, attribute);
    strcpy(attribute, "");
    char *delim = " ";
    char *pch;
    pch = strtok(temp, delim);
    while(pch != NULL){
        // printf("%s\n", pch);
        if(!strcmp(pch, "I") || !strcmp(pch, "I,")){
            strcat(attribute, "I");
        }
        else if(!strcmp(pch, "F") || !strcmp(pch, "F,")){
            strcat(attribute, "F");
        }
        else if(!strcmp(pch, "S") || !strcmp(pch, "S, ")){
            strcat(attribute, "Ljava/lang/String;");
        }
        else if(!strcmp(pch, "B") || !strcmp(pch, "B, ")){
            strcat(attribute, "I");
        }
        pch = strtok(NULL, delim);
    }
    // printf("after %s\n", attribute);
}

/* code generation functions */
void gencode_function(char* input) {
    fputs(input, file);
}

/* handle casting */
char* casting(char* value, int type){
    int i;
    if(type == 0){   // int
        // check if there is a dot
        for(i = 0; i < strlen(value); i++){
            if(value[i] == '.') {   // if yes, change to int
                value[i] = '\0';
                break;
            }
        }
    }
    else{           // float
        int dot = 0;
        // check if there is a dot
        for(i = 0; i < strlen(value); i++){
            if(value[i] == '.') {   // if yes, dot = 1
                dot = 1;
                break;
            }
        }
        if(!dot){   // if there is no dot, add .0 to it
            strcat(value, ".0\0");
        }
    }
    return value;
    
}

int j_load_var(char* id){
    struct symbols *temp;
    char out_str[200];
    int type = -1;
    int scope = scope_num, index;
    
    while(scope >= 0){
        temp = &table[scope];
        if(table[scope].symbol_num == 0){
            scope--;
            continue;
        }
        while(temp != NULL){
            if(!strcmp(temp->name, id)){
                index = temp->index;
                if(!strcmp(temp->type, "I"))  type = 0;
                else if(!strcmp(temp->type, "F"))  type = 1;
                else if(!strcmp(temp->type, "S"))  type = 2;
                else if(!strcmp(temp->type, "B"))  type = 3;
                break;
            }
            temp = temp->next;
        }
        if(type >= 0) break;
        scope--;
    }
    // printf("%d\n", type);
    switch(type){
        case 0:
            if(scope == 0)  sprintf(out_str, "\tgetstatic compiler_hw3/%s I\n", id);
            else sprintf(out_str, "\tiload %d\n", index);
            gencode_function(out_str);
            break;
        case 1:
            if(scope == 0)  sprintf(out_str, "\tgetstatic compiler_hw3/%s F\n", id);
            else sprintf(out_str, "\tfload %d\n", index);
            gencode_function(out_str);
            break;
        case 2:
            if(scope == 0)  sprintf(out_str, "\tgetstatic compiler_hw3/%s Ljava/io/PrintStream;\n", id);
            else sprintf(out_str, "\taload %d\n", index);
            gencode_function(out_str);
            break;
        case 3:
            if(scope == 0)  sprintf(out_str, "\tgetstatic compiler_hw3/%s I\n", id);
            else sprintf(out_str, "\tiload %d\n", index);
            gencode_function(out_str);
            break;
    }
    
    return type;
}

void j_store_var(char* id, int index, char* type, int scope){
    //printf("store %d %s %s\n", index, id, type);
    char out_str[200];

    if(!strcmp(type, "I")){
        if(scope == 0)  sprintf(out_str, "\tputstatic compiler_hw3/%s I\n", id);
        else    sprintf(out_str, "\tistore %d\n", index); 
    }
    else if(!strcmp(type, "F")){
        if(scope == 0)  sprintf(out_str, "\tputstatic compiler_hw3/%s F\n", id);
        else    sprintf(out_str, "\tfstore %d\n", index); 
    }
    else if(!strcmp(type, "S")){
        if(scope == 0)  sprintf(out_str, "\tputstatic compiler_hw3/%s Ljava/io/PrintStream;\n", id);
        else    sprintf(out_str, "\tastore %d\n", index); 
    }
    else if(!strcmp(type, "B")){
        if(scope == 0)  sprintf(out_str, "\tputstatic compiler_hw3/%s I\n", id);
        else    sprintf(out_str, "\tistore %d\n", index); 
    }

    gencode_function(out_str);
}

int j_add_expr(char* left_type, char* right_type, char* operation){
    // printf("expr %s %s %s\n", left_type, right_type, operation);
    char out_str[200];
    int return_type = -1;

    if(!strcmp(left_type, "I") && !strcmp(right_type, "I")){
        if(!strcmp(operation, "ADD"))   sprintf(out_str, "\tiadd\n");
        else if(!strcmp(operation, "SUB"))   sprintf(out_str, "\tisub\n");
        // printf("%s\n", out_str);
        return_type = 0;
    }
    else if(!strcmp(left_type, "F") && !strcmp(right_type, "F")){
        if(!strcmp(operation, "ADD"))   sprintf(out_str, "\tfadd\n");
        else if(!strcmp(operation, "SUB"))   sprintf(out_str, "\tfsub\n");
        // printf("%s\n", out_str);
        return_type = 1;
    }
    else if(!strcmp(left_type, "I") && !strcmp(right_type, "F")){
        sprintf(out_str, "\tswap\n\ti2f\n\tswap\n");
        if(!strcmp(operation, "ADD"))   strcat(out_str, "\tfadd\n");
        else if(!strcmp(operation, "SUB"))   strcat(out_str, "\tfsub\n");
        // printf("%s\n", out_str);
        return_type = 1;
    }
    else if(!strcmp(left_type, "F") && !strcmp(right_type, "I")){
        sprintf(out_str, "\ti2f\n");
        if(!strcmp(operation, "ADD"))   strcat(out_str, "\tfadd\n");
        else if(!strcmp(operation, "SUB"))   strcat(out_str, "\tfsub\n");
        // printf("%s\n", out_str);
        return_type = 1;
    }
    gencode_function(out_str);

    return return_type;
}

int j_mul_expr(char* left_type, char* right_type, char* operation){
    // printf("expr %s %s %s\n", left_type, right_type, operation);
    char out_str[200];
    int return_type = -1;

    if(!strcmp(left_type, "I") && !strcmp(right_type, "I")){
        if(!strcmp(operation, "MUL"))   sprintf(out_str, "\timul\n");
        else if(!strcmp(operation, "DIV"))   sprintf(out_str, "\tidiv\n");
        else if(!strcmp(operation, "REM"))   sprintf(out_str, "\tirem\n");
        // printf("%s\n", out_str);
        return_type = 0;
    }
    else if(!strcmp(left_type, "F") && !strcmp(right_type, "F")){
        if(!strcmp(operation, "MUL"))   sprintf(out_str, "\tfmul\n");
        else if(!strcmp(operation, "DIV"))   sprintf(out_str, "\tfdiv\n");
        else if(!strcmp(operation, "REM"))   yyerror("Only int can do REM!\n");
        // printf("%s\n", out_str);
        return_type = 1;
    }
    else if(!strcmp(left_type, "I") && !strcmp(right_type, "F")){
        sprintf(out_str, "\tswap\n\ti2f\n\tswap\n");
        if(!strcmp(operation, "MUL"))   strcat(out_str, "\tfmul\n");
        else if(!strcmp(operation, "DIV"))   strcat(out_str, "\tfdiv\n");
        else if(!strcmp(operation, "REM"))   yyerror("Only int can do REM!\n");
        // printf("%s\n", out_str);
        return_type = 1;
    }
    else if(!strcmp(left_type, "F") && !strcmp(right_type, "I")){
        sprintf(out_str, "\ti2f\n");
        if(!strcmp(operation, "MUL"))   strcat(out_str, "\tfmul\n");
        else if(!strcmp(operation, "DIV"))   strcat(out_str, "\tfdiv\n");
        else if(!strcmp(operation, "REM"))   yyerror("Only int can do REM!\n");
        // printf("%s\n", out_str);
        return_type = 1;
    }
    gencode_function(out_str);

    return return_type;
}

void j_assign(char* id, char* left_type, char* right_type){
    //printf("assign %s %s\n", id, left_type);
    struct symbols *temp;
    char out_str[200];
    int scope = scope_num;
    int index = -1;

    while(scope >= 0){
        temp = &table[scope];
        if(table[scope].symbol_num == 0){
            scope--;
            continue;
        }
        while(temp != NULL){
            if(!strcmp(temp->name, id)){
                index = temp->index;
                break;
            }
            temp = temp->next;
        }
        if(index >= 0) break;
        scope--;
    }
    // printf("in assign %d left %s r %s\n", index, left_type, right_type);
    if(!strcmp(left_type, "I") && !strcmp(right_type, "I")){        
    }
    else if(!strcmp(left_type, "F") && !strcmp(right_type, "F")){
    }
    else if(!strcmp(left_type, "I") && !strcmp(right_type, "F")){
        strcpy(out_str, "\tf2i\n");
        gencode_function(out_str);
    }
    else if(!strcmp(left_type, "F") && !strcmp(right_type, "I")){
        strcpy(out_str, "\ti2f\n");
        gencode_function(out_str);
    }
    else if(!strcmp(right_type, "NULL")){
        if(!strcmp(left_type, "I")) strcpy(out_str, "\tldc 0\n");
        else if(!strcmp(left_type, "F")) strcpy(out_str, "\tldc 0.0\n");
        else if(!strcmp(left_type, "B")) strcpy(out_str, "\tldc 0\n");
        else if(!strcmp(left_type, "S")) strcpy(out_str, "\tldc \"\"\n");
        gencode_function(out_str);
    }
    j_store_var(id, index, left_type, scope);

}

/* generating the variable declaration */
void j_global_var_declaration(char* id, char *value, char* constant_type){
    char output[200];
    /* classify with variable type */
    if(!strcmp(constant_type, "I")){
        if(!strcmp(value, "NULL")){
            sprintf(output, ".field public static %s I = 0\n", id); // not initialized, assign 0
            gencode_function(output);      
        }
        /* check type casting */
        else{
            casting(value, 0);
            sprintf(output, ".field public static %s I = %s\n", id, value);
            gencode_function(output);
        }
    }
    else if(!strcmp(constant_type, "F")){
        if(!strcmp(value, "NULL")){
            sprintf(output, ".field public static %s F = 0.0\n", id);
            gencode_function(output);
        }
        else{
            /* check type casting */
            casting(value, 1);
            sprintf(output, ".field public static %s F = %s\n", id, value);
            gencode_function(output);
        }
    }
    else if(!strcmp(constant_type, "S")){
        char temp[50];
        int len = strlen(value);
        value[len-1] = '\0';    // take out the last '/'
        sprintf(temp, "\"%s\"", value); // add ""
        sprintf(output, ".field public static %s Ljava/lang/String; = %s\n", id, temp);
        gencode_function(output);
        strcpy(value, temp);
    }
    else if(!strcmp(constant_type, "B")){        
        if(!strcmp(value, "NULL"))   fprintf(file, ".field public static %s I = 1\n", id);  // not initialize
        int len = strlen(value);
        value[len-1] = '\0';    // take out the last '/'
        if(!strcmp(value, "true")) sprintf(output, ".field public static %s I = 1\n", id);
        else sprintf(output, ".field public static %s I = 0\n", id);
        gencode_function(output);
    }
    
}


void j_local_var_declaration(char* id, char *value, char* constant_type){
    // printf("local %s %s %s\n", constant_type, id, value);
    return;
}

void j_func_declaration(char* id, char* return_type, char* parameters){
    char out_str[200];
    char para_type[50];
    char ret_type[10];
    /* parameters */
    if(!strcmp(parameters, "NULL")){
        strcpy(para_type, "[Ljava/lang/String;");
    }
    else{
        strcpy(para_type, parameters);        
        analyze_parameters(para_type);
    }
    /* return type */
    if(!strcmp(return_type, "I")) strcpy(ret_type, "I");
    else if(!strcmp(return_type, "F"))  strcpy(ret_type, "F");
    else if(!strcmp(return_type, "V"))   strcpy(ret_type, "V");
    else if(!strcmp(return_type, "B"))   strcpy(ret_type, "I");

    sprintf(out_str, ".method public static %s(%s)%s\n.limit stack 50\n.limit locals 50\n", id, para_type, ret_type);
    // printf("%s\n", out_str);
    gencode_function(out_str);
    strcpy(parameters, para_type);
}

void j_func_call(char* id){
    char out_str[300];
    /* get attribute and return type */
    char attribute[10];
    char ret_type[10];
    lookup_function(id, ret_type, attribute);
    sprintf(out_str, "\tinvokestatic compiler_hw3/%s(%s)%s\n", id, attribute, ret_type);
    // strcat(out_str, tmp_str);
    gencode_function(out_str);
}

/* generating the print statement */
void j_print(char* item, char *type){
    char out_str[200];

    /* print string constants */
    if(item[0] == '\"' && !strcmp(type, "string")){
        sprintf(out_str, "ldc %s\ngetstatic java/lang/System/out Ljava/io/PrintStream;\nswap\ninvokevirtual java/io/PrintStream/println(Ljava/lang/String;)V\n", item);
    }
    /* print variable */
    else if(!isdigit(item[0])){
        int index = search_index(item, scope_num);      // get index
        // printf("index %d\n", index);
        if(index >= 0){    // local
            if(!strcmp(type, "I")){
                sprintf(out_str, "\tiload %d\n\tgetstatic java/lang/System/out Ljava/io/PrintStream;\n\tswap\n\tinvokevirtual java/io/PrintStream/println(I)V\n", index);
            }
            else if(!strcmp(type, "F")){
                sprintf(out_str, "\tfload %d\n\tgetstatic java/lang/System/out Ljava/io/PrintStream;\n\tswap\n\tinvokevirtual java/io/PrintStream/println(F)V\n", index);
            }
            else if(!strcmp(type, "S")){
                sprintf(out_str, "\taload %d\n\tgetstatic java/lang/System/out Ljava/io/PrintStream;\n\tswap\n\tinvokevirtual java/io/PrintStream/println(Ljava/lang/String;)V\n", index);
                gencode_function(out_str);
            }
            else if(!strcmp(type, "I")){
                sprintf(out_str, "\tiload %d\n\tgetstatic java/lang/System/out Ljava/io/PrintStream;\n\tswap\n\tinvokevirtual java/io/PrintStream/println(I)V\n", index);
            }
        }
        else{       // global
            if(!strcmp(type, "I")){
                sprintf(out_str, "\tgetstatic compiler_hw3/%s I\n\tgetstatic java/lang/System/out Ljava/io/PrintStream;\n\tswap\n\tinvokevirtual java/io/PrintStream/println(I)V\n", item);
            }
            else if(!strcmp(type, "F")){
                sprintf(out_str, "\tgetstatic compiler_hw3/%s F\n\tgetstatic java/lang/System/out Ljava/io/PrintStream;\n\tswap\n\tinvokevirtual java/io/PrintStream/println(F)V\n", item);
            }
            else if(!strcmp(type, "S")){
                sprintf(out_str, "\tgetstatic compiler_hw3/%s Ljava/lang/String;\n\tgetstatic java/lang/System/out Ljava/io/PrintStream;\n\tswap\n\tinvokevirtual java/io/PrintStream/println(Ljava/lang/String;)V\n", item);
            }
            else if(!strcmp(type, "I")){
                sprintf(out_str, "\tgetstatic compiler_hw3/%s I\n\tgetstatic java/lang/System/out Ljava/io/PrintStream;\n\tswap\n\tinvokevirtual java/io/PrintStream/println(I)V\n", item);
            }
        }

    }
    /* print number constants */
    else{
        if(!strcmp(type, "I")){
            sprintf(out_str, "\tldc %s\n\tgetstatic java/lang/System/out Ljava/io/PrintStream;\n\tswap\n\tinvokevirtual java/io/PrintStream/println(I)V\n", item);
        }
        else if(!strcmp(type, "F")){
            sprintf(out_str, "\tldc %s\n\tgetstatic java/lang/System/out Ljava/io/PrintStream;\n\tswap\n\tinvokevirtual java/io/PrintStream/println(F)V\n", item);
        }
        else if(!strcmp(type, "B")){
            sprintf(out_str, "\tldc %s\n\tgetstatic java/lang/System/out Ljava/io/PrintStream;\n\tswap\n\tinvokevirtual java/io/PrintStream/println(I)V\n", item);
        }
        else if(!strcmp(type, "S")){
            sprintf(out_str, "\tldc %s\n\tgetstatic java/lang/System/out Ljava/io/PrintStream;\n\tswap\n\tinvokevirtual java/io/PrintStream/println(Ljava/lang/String;)V\n", item);
        }
    }
    gencode_function(out_str);
}

int is_float(char* num){
    int result = 0;
    char temp[20];
    strcpy(temp, num);
    int i;
    for(i = 0; i < strlen(temp); i++){
        if(temp[i] == '.'){
            result = 1;
            break;
        }
    }
    return result;
}