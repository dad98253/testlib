#include <jni.h>
#include <string>
#include "sha2.h"


void test(const char *vector, unsigned char *digest,
          unsigned int digest_size)
{
    char output[2 * SHA512_DIGEST_SIZE + 1];
    int i;

    output[2 * digest_size] = '\0';

    for (i = 0; i < (int) digest_size ; i++) {
        sprintf(output + 2 * i, "%02x", digest[i]);
    }

    fprintf(stderr,"H: %s\n", output);
    if (strlen(vector) != strlen(output)) fprintf(stderr,"vector lengths don't agree\nstrlen(vector)=%i, strlen(output)=%i\n",(int)strlen(vector),(int)strlen(output));
    if (strcmp(vector, output)) {
        fprintf(stderr, "Test failed.\n");
        fprintf(stderr, "vector=\"%s\"\n",vector);
        fprintf(stderr, "output=\"%s\"\n",output);
//        exit(EXIT_FAILURE);
    }
}

extern "C" JNIEXPORT jstring JNICALL
Java_net_kuras_1sea_testlib_MainActivity_stringFromJNI(
        JNIEnv *env,
        jobject /* this */) {
    static const char *vectors[4][5] =
            {   /* SHA-224 */
                    {
                            "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7",
                            "75388b16512776cc5dba5da1fd890150b0c6455cb4f58b1952522525",
                            "20794655980c91d8bbb4c1ea97618a4bf03f42581948b2ee4ee7ad67",
                            "0",
                            "d14a028c2a3a2bc9476102bb288234c415a2b01f828ea62ac5b3e42f",
                    },
                    /* SHA-256 */
                    {
                            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
                            "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
                            "0",
                            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                    },
                    /* SHA-384 */
                    {
                            "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed"
                            "8086072ba1e7cc2358baeca134c825a7",
                            "09330c33f71147e83d192fc782cd1b4753111b173b3b05d22fa08086e3b0f712"
                            "fcc7c71a557e2db966c3e9fa91746039",
                            "9d0e1809716474cb086e834e310a4a1ced149e9c00f248527972cec5704c2a5b"
                            "07b8b3dc38ecc4ebae97ddd87f3d8985",
                            "0",
                            "38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da"
                            "274edebfe76f65fbd51ad2f14898b95b",
                    },
                    /* SHA-512 */
                    {
                            "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
                            "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
                            "8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018"
                            "501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909",
                            "e718483d0ce769644e2e42c7bc15b4638e1f98b13b2044285632a803afa973eb"
                            "de0ff244877ea60a4cb0432ce577c31beb009c5c2c49aa2e4eadb217ad8cc09b",
                            "523df363aa22c25478a478d25e6945f842509df8b77b0c755a40538a9a239ae1"
                            "78b3225f516bdb9e29f6d1cb7de4f2cf74e67fd85f6d9817c48890d686d51838",
                            "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce"
                            "47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e",
                    }
            };
    static const char * hithere ="Hi There";  // should be (hex) 523df363aa22c25478a478d25e6945f842509df8b77b0c755a40538a9a239ae178b3225f516bdb9e‌​29f6d1cb7de4f2cf74e67fd85f6d9817c48890d686d51838
    static const char * blankstr ="";  // should be:
/*
 *
SHA224("")
0x d14a028c2a3a2bc9476102bb288234c415a2b01f828ea62ac5b3e42f
SHA256("")
0x e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
SHA384("")
0x 38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b
SHA512("")
0x cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e
SHA512/224("")
0x 6ed0dd02806fa89e25de060c19d3ac86cabb87d6a0ddd05c333b84f4
SHA512/256("")
0x c672b8d1ef56ed28ab87c3622c5114069bdd3ad7b8f9737498d0c01ecef0967a
 *
 */
#ifdef DOTIMING
#define NUMOFLOOPS	10000
#else
#define NUMOFLOOPS	1
#endif

    unsigned char digest[SHA512_DIGEST_SIZE];
    unsigned char intelmessage[SHA512_DIGEST_SIZE];
    time_t mytime;
    int i;
    int errflag = 1;
    unsigned char *message3;
    unsigned int message3_len = 1000000;

    message3 = (unsigned char *)malloc(message3_len);
    if (message3 == NULL) {
        fprintf(stderr, "Can't allocate memory\n");
        goto myerror;
    }
    memset(message3, 'a', message3_len);
// test linux hash routine
    fprintf(stderr,"Test linux passwd hashing...\n");


    mytime = time(NULL);
    fprintf(stderr,"start time: %s",ctime(&mytime));
    for (i=0;i<NUMOFLOOPS;i++) sha512(message3, message3_len, digest);
    mytime = time(NULL);
    fprintf(stderr,"end   time: %s",ctime(&mytime));
    test(vectors[3][2], digest, SHA512_DIGEST_SIZE);
    sha512((const unsigned char *)hithere, strlen(hithere), digest);
    test(vectors[3][3], digest, SHA512_DIGEST_SIZE);
    sha512((const unsigned char *)blankstr, strlen(blankstr), digest);
    test(vectors[3][4], digest, SHA512_DIGEST_SIZE);
    fprintf(stderr,"\n");




    errflag = 0;
myerror:
    std::string hello;
    if (errflag) {
        hello = "error";
    } else {
        hello = "Hello from C+++";
    }
    return env->NewStringUTF(hello.c_str());
}
