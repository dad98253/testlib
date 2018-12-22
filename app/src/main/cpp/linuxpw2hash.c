/*
 * linuxpw2hash.c
 *
 *  Created on: Jul 6, 2017
 *      Author: dad
 */


#include <stdio.h>
#include <string.h>
#include <malloc.h>
#include <ctype.h>
#include "sha2.h"


#define MAX(x, y) (((x) < (y)) ? (y) : (x))

int DecompressStr(char *MasterPW, char *MasterPWComp,int lenMasterPWComp, int option);
void debug_dump_stuff_msg_f(const void *msg, void *x, unsigned int size);

int doHAsh ( char * salt, char * password , int rounds)
{
	char * intermediate ;
	char * alternate ;
	char * Sbytesstring ;
	char * Pbytesstring ;
	int saltlen = 0;
	int pwlen = 0;
	int intermediatelen;
    unsigned char alternatedigest[SHA512_DIGEST_SIZE+1] = {0};
    unsigned char intermediatedigest[SHA512_DIGEST_SIZE+1] = {0};
    unsigned char Sbytes[SHA512_DIGEST_SIZE+1] = {0};
    unsigned char Pbytes[SHA512_DIGEST_SIZE+1] = {0};
    unsigned char hash[SHA512_DIGEST_SIZE+5] = {0};
    int i;
    int xtraintlen=0;
    int Sfactor;
    int Resultlen=0;
    unsigned char byteorder[] = {
    	      63,  62, 20, 41,  40, 61, 19,  18, 39, 60,  59, 17, 38,  37, 58, 16,  15, 36, 57,  56, 14, 35, \
    	           34, 55, 13,  12, 33, 54,  53, 11, 32,  31, 52, 10,   9, 30, 51,  50,  8, 29,  28, 49,  7, \
    	            6, 27, 48,  47,  5, 26,  25, 46,  4,   3, 24, 45,  44,  2, 23,  22, 43,  1,   0, 21, 42  \
    		};


	if ( ( saltlen = strlen(salt)     ) == 0 ) return 1;
	if ( ( pwlen   = strlen(password) ) == 0 ) return 2;
	for (i = pwlen; i > 0; i >>= 1) {
		if ((i & 1) != 0) {
			xtraintlen+=SHA512_DIGEST_SIZE;
		} else {
			xtraintlen+=pwlen;
		}
	}

	intermediate = (char *)malloc(MAX(saltlen + 2*pwlen + 2 + xtraintlen, 4*SHA512_DIGEST_SIZE +2));
	alternate    = (char *)malloc(saltlen + 2*pwlen + 2);
	Sbytesstring = (char *)malloc(saltlen*(256+16)  + 2);
	Pbytesstring = (char *)malloc(pwlen*pwlen       + 2);

	intermediate[0] = '\000';

	strcpy(intermediate, password);
	strcat(intermediate, salt);

	alternate[0]    = '\000';

	strcpy(alternate, intermediate);
	strcat(alternate, password);

	sha512((const unsigned char *) alternate, strlen(alternate), alternatedigest);
//debug_dump_stuff_msg_f("alternatedigest - pw/salt/pw", alternatedigest, SHA512_DIGEST_SIZE);
	intermediatelen = strlen(intermediate);
	if ( pwlen > SHA512_DIGEST_SIZE ) {
		for (i=0;i< (pwlen / SHA512_DIGEST_SIZE);i++) {
			memcpy(intermediate+intermediatelen, alternatedigest, SHA512_DIGEST_SIZE);
			intermediatelen+=SHA512_DIGEST_SIZE;
		}
	}
	memcpy(intermediate+intermediatelen, alternatedigest, pwlen%SHA512_DIGEST_SIZE);
	intermediatelen+=(pwlen%SHA512_DIGEST_SIZE);

	for (i = pwlen; i > 0; i >>= 1) {
		if ((i & 1) != 0) {
			memcpy(intermediate+intermediatelen, alternatedigest, SHA512_DIGEST_SIZE);
			intermediatelen+=SHA512_DIGEST_SIZE;
		} else {
			strcat(intermediate, password);
			intermediatelen+=pwlen;
		}
	}

	sha512((const unsigned char *) intermediate, intermediatelen, intermediatedigest);
//debug_dump_stuff_msg_f("intermediatedigest - pw/salt/alt-digest", intermediatedigest, SHA512_DIGEST_SIZE);
	Sfactor = 16 + (int)intermediatedigest[0];
	Sbytesstring[0] = '\000';
	for (i = 0; i < Sfactor; i++) strcat(Sbytesstring, salt);
	sha512((const unsigned char *) Sbytesstring, strlen(Sbytesstring), Sbytes);
//debug_dump_stuff_msg_f("Sbytes", Sbytes, saltlen);
	Pbytesstring[0] = '\000';
	for (i = 0; i < pwlen; i++) strcat(Pbytesstring, password);
	sha512((const unsigned char *) Pbytesstring, strlen(Pbytesstring), Pbytes);

//debug_dump_stuff_msg_f("Pbytes", Pbytes, pwlen);

	for (i = 0; i < rounds; i++) {
		intermediate[0]='\000';
		intermediatelen=0;

		if (i & 1) {
			memcpy(intermediate, Pbytes, pwlen);
			intermediatelen+=pwlen;
		} else {
			memcpy(intermediate, intermediatedigest, SHA512_DIGEST_SIZE);
			intermediatelen+=SHA512_DIGEST_SIZE;
		}
		if (i % 3) {
			memcpy(intermediate+intermediatelen, Sbytes, saltlen);
			intermediatelen+=saltlen;
		}
		if (i % 7) {
			memcpy(intermediate+intermediatelen, Pbytes, pwlen);
			intermediatelen+=pwlen;
		}
		if (i & 1) {
			memcpy(intermediate+intermediatelen, intermediatedigest, SHA512_DIGEST_SIZE);
			intermediatelen+=SHA512_DIGEST_SIZE;
		} else {
			memcpy(intermediate+intermediatelen, Pbytes, pwlen);
			intermediatelen+=pwlen;
		}
//if (i==(rounds-1)) debug_dump_stuff_msg_f("second to last round)", intermediatedigest, SHA512_DIGEST_SIZE);
		sha512((const unsigned char *) intermediate, intermediatelen, intermediatedigest);
	}
//debug_dump_stuff_msg_f("final (pre shuffle)", intermediatedigest, SHA512_DIGEST_SIZE);

	printf("$6$");
	if (rounds!=5000) printf("rounds=%i$",rounds);
	printf("%s$",salt);
	for (i=0;i<64;i++) hash[i] = intermediatedigest[byteorder[i]];
//debug_dump_stuff_msg_f("final (after shuffle)", hash, SHA512_DIGEST_SIZE);
	intermediate[0]='\000';
	if ( ( Resultlen = DecompressStr(intermediate, (char *)hash,SHA512_DIGEST_SIZE, 0) ) == 0) {
		fprintf(stderr,"error in DecompressStr\n");
		return(1);
	}
	while ( Resultlen < 86) {
		intermediate[Resultlen] = '=';
		intermediate[Resultlen+1] = '\000';
		Resultlen++;
	}
	printf("%s\n",intermediate);

	free(intermediate);
	free(alternate);
	free(Sbytesstring);
	free(Pbytesstring);

	return 0;
}


// decompress an ascii string that was compressed using the above routine
// MasterPWComp points to the input (compressed) string .  NOTE: this string is input/ouput & MUST be 4 bytes longer than lenMasterPWComp!!!
// MasterPW is the pointer to where the decompressed output (ascii) string should go
// option is an interger flag that indicates whether or not the first 6 bits of each output long word
// will contain random data. This is done to keep identical strings from encoding the same (well, most of the time...)
// option = 1 => assume random data was added
// option = 0 => assume no random data was added
// The function returns the length of the output string (in 8 bit bytes) or zero if an error is detected
int DecompressStr(char *MasterPW, char *MasterPWComp,int lenMasterPWComp, int option)
{
	int lenStrIn,lenStrOut,i,j,k,rawChar,Xchar;
	char TempStr[1029];
 //   char b64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    char b64[] = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";


	lenStrIn = lenMasterPWComp;
	MasterPWComp[lenStrIn]  ='\000';
	MasterPWComp[lenStrIn+1]='\000';
	MasterPWComp[lenStrIn+2]='\000';
	MasterPWComp[lenStrIn+3]='\000';
// transform the chracters of the input string from the six bit character set to eight bit ascii
// Only printable characters are recognized because the six bit code does not include any non-printing ones.
// Input characters and numbers are stored as a 6 bit number 1-63. Zero is used as an escape code to indicate a non-alphanumeric
// character. The total number of recognized characters is 96. Ouput characters are 8 bit ascii codes.
// Now compress the string of six bit characters into eight bit bytes. This is done 3 bytes at a time.
// Note that the end of the temporary string is padded with 4 zero bytes.

// first, expand the 6 bit string into an 8 bit string:
	if( (lenStrIn/3*4+2) > 1029 ) return 0;
	j=0;
	for (i=lenStrIn-3;(i+3)>0;i-=3){
		TempStr[j] = '\000';
		TempStr[j] =  MasterPWComp[i+2] & 63;
		j++;
		TempStr[j] = '\000';
		if(i<-1){
			TempStr[j] = ((MasterPWComp[i+2] >> 6 ) & 3);
			j++;
			continue;
		} else {
			TempStr[j] = ((MasterPWComp[i+1] & 15 ) << 2) | ((MasterPWComp[i+2] >> 6 ) & 3);
		}
		j++;
		TempStr[j] = '\000';
		if(i<0) {
			TempStr[j] = ((MasterPWComp[i+1] >> 4 ) & 15);
			j++;
			continue;
		} else {
			TempStr[j] = ((MasterPWComp[i] & 3 ) << 4) | ((MasterPWComp[i+1] >> 4 ) & 15);
		}
		j++;
		TempStr[j] = '\000';
		TempStr[j] = (MasterPWComp[i] >> 2) & 63;
		j++;
	}
// set lenStrOut to the exact number of bytes used in the output string.
	TempStr[j] = '\000';
	j++;
	do {
		j--;
	} while ( TempStr[j] == '\000' );
	lenStrOut = j+1;

	for (i=0;i<(lenStrOut+1);i++) MasterPW[i] = TempStr[i];
// convert to ascii
	j=0;
	for (i=0;i<lenStrOut;i++){
		rawChar=MasterPW[i];
		if (rawChar > 63 ) {
			fprintf(stderr,"String contains illegal characters!\n");
			return (0);
		}
		Xchar=(int)(*(b64+rawChar));
		MasterPW[j] = (char)Xchar;
		j++;
	}
	MasterPW[j] = '\000';
	lenStrOut = strlen(MasterPW);
// strip out any bogus characters
	if ( option == 1 ) {
		j=0;
		k=0;
		for (i=0;i<lenStrOut;i++){
			if ( (i%11) != 0 ){
				MasterPW[j] = MasterPW[i];
				j++;
			} else {
				k++;
			}
		}
		MasterPW[j] = '\000';
		lenStrOut = strlen(MasterPW);
	}

	return(lenStrOut);
}


void debug_dump_stuff_noeol_f(void *x, unsigned int size)
{
	unsigned int i;

	if ( x ) {
		for(i=0;i<size;i++)
		{
			fprintf(stderr,"%02x", ((unsigned char*)x)[i]);
			if( (i%4)==3 ) {
				fprintf(stderr," ");
			}
		}
		fprintf(stderr," ___ ");
		for(i=0;i<size;i++)
		{
			if ( isprint(((unsigned char*)x)[i]) ) {
				fprintf(stderr,"%c", ((unsigned char*)x)[i]);
			} else {
				fprintf(stderr,".");
			}
			if( (i%4)==3 ) {
				fprintf(stderr," ");
			}
		}
	} else {
		fprintf(stderr,"debug_dump_fmt: bad call, argument pointer is %p\n", x);
	}

	return;
}

void debug_dump_stuff_f(void* x, unsigned int size)
{


	debug_dump_stuff_noeol_f(x,size);
	fprintf(stderr,"\n");
}

void debug_dump_stuff_msg_f(const void *msg, void *x, unsigned int size)
{


	fprintf(stderr,"%s\n",(char *)msg);

	if ( x ) {
		fprintf(stderr,"[0-%i] starting at address %p: \n",size ,x );
		debug_dump_stuff_f(x , size);
	} else {
		fprintf(stderr,"%s points to -nil-, dump of %s[0-%i] not possible!\n", (char *)msg, (char *)msg, size);
	}

	return;
}

