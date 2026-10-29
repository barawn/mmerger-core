function [ram_init,ninit] = file_to_bram_init(rbit,si_addr,si_data,nadr)

    ibit = 256;%number of bits on BRAM init line
    ncat = ibit/rbit;%number of ROM lines to concatenate on init line
    niln = ceil(nadr/ncat);%number of BRAM init lines
    nrem = mod(nadr,ncat);
    
    tsp = {' '};
    tct = {' &'};
    tcp = {'"'};
    tbt = string(strcat(num2str(rbit),'UX"0"'));
    tht = string(strcat(num2str(rbit),'UX"'));
    rom_data = strings(1,nadr);
    ram_init = strings(1,niln);    
    tctrl = strings(1,ncat);
    tlen = strings(1,ncat);    
    iadr = 1;
    iinit = 1;
    
    %concatenate address and data    
    for i= 1:1:nadr
        rom_data = strcat(si_addr,si_data);
    end;
    
    for i=1:1:niln
        for j = 1:1:ncat 
            %find end of line
            if j == 1
                tctrl(1,j) = strcat(tht,rom_data(iadr),tcp);
            elseif j < ncat
                if (i==niln) & (nrem>0) & (j>nrem)
                    tctrl(1,j) = strcat(tbt,tct);
                else
                    tctrl(1,j) = strcat(tht,rom_data(iadr),tcp,tct);
                end;
            else
                if (i==niln) & (nrem>0) & (j>nrem)
                    tctrl(1,j) = strcat(tbt,tct);
                else
                    tctrl(1,j) = strcat(tht,rom_data(iadr),tcp,tct);
                end;
            end;                     
            iadr = iadr + 1;
        end;
        %control text
        ram_init(1,iinit) = strjoin(fliplr(tctrl));
        iinit = iinit + 1;
    end;
    %remove spurious increment
    ninit = iinit - 1;

end
        