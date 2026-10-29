function [A,D,sz] = parse_file(fname,awdt,dwdt)

    %Read the register CSV file created by Clock Builder Pro
    %R1 = 24;%firt configruation reigster (see text in file)
    %RN = 541;%last configruation reigster (see text in file)

    fid = fopen(fname);
    frow = 1;
    tline = fgetl(fid);
    tvar(frow) = string(tline);
    while ischar(tline)        
        tline = fgetl(fid);
        frow = frow + 1;
        tvar(frow) = string(tline);                
    end;
    fclose(fid);
    
    %raw = tvar(R1:RN);%grab the configuration registers
    raw = tvar;%grab the configuration registers
    mrow = 0;
    %for i=1:1:((RN-R1)+1)
    for i=1:1:frow
        %find comments and/or non-hex values
        comloc = strfind(raw(i),'0x') ;
        if ~isempty(comloc)
            mrow = mrow+1;
            tmp_vec = sscanf(raw(i),'%x,%x');%get thr addr,data hex values        
            A(mrow) = string(dec2hex(tmp_vec(1),ceil(awdt/4)));
            D(mrow) = string(dec2hex(tmp_vec(2),ceil(dwdt/4)));
        end;
    end;
    sz = length(A);    

end

        