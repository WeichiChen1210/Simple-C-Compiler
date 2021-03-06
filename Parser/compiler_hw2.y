/*	Definition section */
%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern int yylineno;
extern int yylex();
extern char* yytext;   // Get current token from lex
extern char buf[256];  // Get current code line from lex

int sem_err_flag = -1;
int syn_err_flag = 0;
char error_id[50];
int scope_num = 0;

struct symbols{
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

struct symbols table[200];

/* Symbol table function - you can add new function if needed. */
int lookup_symbol(char *id, int scope, int mode);
void create_symbol();
void insert_symbol(char *name, char *kind, char *type, int scope, char *attribute);
void dump_symbol(int scope);
void semantic_errors(int kind_of_error, int offset);    // print semantic errors messages
void delete_parameter_symbol(int scope);                // delete the parameter of forwarding function
void fill_parameter(int scope, char *id, char *attribute);  // refill the parameters to forwarding functions

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
%type <string> type_specifier declaration_specifiers declarator declaration init_declarator_list init_declarator
%type <string> function_definition parameter_list parameter_declaration
%type <string> postfix_expression primary_expression

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
    | declaration_specifiers declarator compound_statement  {   /* split the string that contains ID and parameter list */
                                                                char *temp; 
                                                                temp = strtok($2, ":");
                                                                /* ID */
                                                                $2 = temp;
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
                                                                /* return 0, insert the symbol */
                                                                else insert_symbol($2, "function", $1, scope_num, temp); 
                                                            }
    | declarator declaration_list compound_statement
    | declarator compound_statement
    | declaration_specifiers declarator SEMICOLON   {   /* forwarding function(encountered at the first time) */
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
                                                        else insert_symbol($2, "function", $1, scope_num, notdef);
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
    : ID                { $$ = strdup(yytext); }
    | LB declarator RB  
    | declarator LSB conditional_expression RSB
    | declarator LSB RSB
    /* attach parameters together */
    | declarator LB in_scope parameter_list RB out_scope { strcat($$, ":"); strcat($$, $4); }
    | declarator LB in_scope identifier_list RB out_scope
    | declarator LB RB  
    ;
/* these 2 states are used to increase and decrease scope level */
in_scope
    : { scope_num++; }
    ;

out_scope
    : { scope_num--; }
    ;

declaration
    : declaration_specifiers SEMICOLON  
    | declaration_specifiers init_declarator_list SEMICOLON     {   /* variable declaration */
                                                                    int result = lookup_symbol($2, scope_num, 0);
                                                                    if(result){
                                                                        // redeclared variable
                                                                        sem_err_flag = 0;
                                                                        strcpy(error_id, $2);
                                                                    }
                                                                    else insert_symbol($2, "variable", $1, scope_num, "NULL");
                                                                }
    ;

identifier_list
    : ID
    | identifier_list COMMA ID
    ;

init_declarator_list
    : init_declarator                               { $$ = $1; }
    | init_declarator_list COMMA init_declarator
    ;

/* statements */
statement
    : compound_statement
    | expression_statement
    | selection_statement
    | iteration_statement
    | jump_statement
    | print_statement
    ;

compound_statement
    : LCB RCB
    | LCB in_scope block_item_list RCB out_scope
    ;

expression_statement
    : COMMA
    | expression SEMICOLON
    ;

selection_statement
    : IF LB expression RB statement
    | IF LB expression RB statement ELSE statement
    ;

iteration_statement
    : WHILE LB expression RB statement
    | FOR LB expression_statement expression_statement RB statement
    | FOR LB expression_statement expression_statement expression RB statement
    ;

jump_statement
    : CONT SEMICOLON
    | BREAK SEMICOLON
    | RET SEMICOLON
    | RET expression SEMICOLON
    ;

print_statement
    : PRINT LB id_stat RB SEMICOLON
    | PRINT LB QUOTA STR_CONST QUOTA RB SEMICOLON
    ;

conditional_expression
    : logical_or_expression
    ;

parameter_list
    : parameter_declaration { $$ = $1; }
    /* attach parameters */
    | parameter_list COMMA parameter_declaration    { $$ = strcat($1, ", "); $$ = strcat($$, $3); }
    ;

init_declarator
    : declarator                    { $$ = $1; }
    | declarator ASGN initializer   { $$ = $1; }
    ;

id_stat
    : ID    {   if(!lookup_symbol(yytext, scope_num, 1)){
                    sem_err_flag = 2;
                    strcpy(error_id, yytext);
                }
            }
    ;

logical_or_expression
    : logical_and_expression
    | logical_or_expression OR logical_and_expression
    ;

expression
    : assignment_expression
    | expression COMMA assignment_expression
    ;

parameter_declaration
    : declaration_specifiers declarator {   /* check parameter*/
                                            if(!lookup_symbol($2, scope_num, 0))
                                                insert_symbol($2, "parameter", $1, scope_num, "NULL");
                                            $$ = $1; 
                                        }
    | declaration_specifiers
    ;

initializer
    : assignment_expression
    | LCB initializer_list RCB
    | LCB initializer_list COMMA RCB
    ;

logical_and_expression
    : inclusive_or_expression
    | logical_and_expression AND inclusive_or_expression
    ;

assignment_expression
    : conditional_expression
    | unary_expression assignment_operator assignment_expression
    ;

initializer_list
    : initializer
    | initializer_list SEMICOLON initializer
    ;

inclusive_or_expression
    : exclusive_or_expression
    ;

unary_expression
    : postfix_expression
    | INC unary_expression
    | DEC unary_expression
    | unary_operator unary_expression
    ;

assignment_operator
    : ASGN
    | ADDASGN
    | SUBASGN
    | MULASGN
    | DIVASGN
    | MODASGN
    ;

exclusive_or_expression
    : and_expression
    ;

postfix_expression
    : primary_expression        {   /* check ID declared or not */
                                    if($1 != NULL) {
                                        if(!lookup_symbol($1, scope_num, 1)){
                                            // undeclared variable
                                            sem_err_flag = 2;
                                            strcpy(error_id, $1);
                                        }
                                    }                               
                                }
    | postfix_expression LSB expression RSB
    | postfix_expression LB RB
    | postfix_expression LB argument_expression_list RB {   /* check function name declared or not */
                                                            if($1 != NULL) {
                                                                if(!lookup_symbol($1, scope_num, 3)){
                                                                    // undeclared function
                                                                    sem_err_flag = 3;
                                                                    strcpy(error_id, $1);
                                                                }
                                                            }  
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
    : equality_expression
    ;

primary_expression
    : ID                        { $$ = strdup(yytext); }
    | I_CONST                   { ; }
    | F_CONST                   { ; }
    | QUOTA STR_CONST QUOTA     { ; }
    | TRUE                      { ; }
    | FALSE                     { ; }
    | LB expression RB          { ; }
    ;

argument_expression_list
    : assignment_expression
    | argument_expression_list COMMA assignment_expression
    ;

equality_expression
    : relational_expression
    | equality_expression EQ relational_expression
    | equality_expression NE relational_expression
    ;

relational_expression
    : additive_expression
    | relational_expression LT additive_expression
    | relational_expression MT additive_expression
    | relational_expression LTE additive_expression
    | relational_expression MTE additive_expression
    ;

additive_expression
    : multiplicative_expression
    | additive_expression ADD multiplicative_expression
    | additive_expression SUB multiplicative_expression
    ;

multiplicative_expression
    : unary_expression
    | multiplicative_expression MUL unary_expression
    | multiplicative_expression DIV unary_expression
    | multiplicative_expression MOD unary_expression
    ;

/* actions can be taken when meet the token or rule */
/* types */
type_specifier
    : INT   { $$ = strdup(yytext); }
    | FLOAT { $$ = strdup(yytext); }
    | BOOL  { $$ = strdup(yytext); }
    | STRING { $$ = strdup(yytext); }
    | VOID  { $$ = strdup(yytext); }
;

%%

/* C code section */
int main(int argc, char** argv)
{
    yylineno = 0;
    create_symbol();
    yyparse();
    /* if there is a syntax error, don't print the last line */
    if(!syn_err_flag){
        dump_symbol(0);
        printf("\nTotal lines: %d \n",yylineno);
    }
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
}

/* initialize the table */
void create_symbol() {
    int i;
    for(i = 0; i < 200; i++){
        strcpy(table[i].name, "HEAD");
        table[i].next = NULL;
        table[i].scope = 0;
        table[i].printed = -1;
        table[i].symbol_num = 0;
        table[i].defined = -1;
    }
}

/* insert symbols */
void insert_symbol(char *name, char *kind, char *type, int scope, char *attribute) {
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
    new_symbol->scope = scope;
    new_symbol->printed = -1;
    new_symbol->next = NULL;
    temp->next = new_symbol;
    table[scope].symbol_num++;

}

/* lookup symbols from scope up to 0 */
int lookup_symbol(char *id, int scope, int mode) {  // mode 0: redeclared variable 1: undeclared variable
                                                    //      2: redeclared function 3: undeclared function
    struct symbols *temp;
    int existed = 0, cur_scope = scope;

    if(!mode || mode == 2){
        temp = &table[scope];
        if(table[scope].symbol_num == 0){
            existed = 0;
        }
        else {
            while(temp != NULL){
                /* if this is a variable already existed */
                if(!strcmp(temp->name, id)){
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
                    break;
                }
                temp = temp->next;
            }
            scope--;
        }
    }
    // return 0: not exist 1: exist 2: forwarding
    return existed;
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

        printf("%-10d%-10s%-12s%-10s%-10d", index++, temp->name, temp->kind, temp->type, temp->scope);
        if(strcmp(temp->attribute, "\0"))    printf("%s\n", temp->attribute);
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