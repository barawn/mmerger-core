clear all;
close all;
fclose('all');
FNAME = '../doc/register_map.xlsx';
SHEET = 'External';

%Read the spreadsheet
[num,txt,raw] = xlsread(FNAME,SHEET,'A2:A72');
name = txt;

[num,txt,raw] = xlsread(FNAME,SHEET,'H2:H72');
N = uint16(num);

[num,txt,raw] = xlsread(FNAME,SHEET,'I2:I72');
B = uint16(num);

[num,txt,raw] = xlsread(FNAME,SHEET,'J2:J72');
M = uint16(num);

[num,txt,raw] = xlsread(FNAME,SHEET,'E2:E72');
default = string(raw);

%Analyze the data without creating HDL
[nrow,ncol] = size(N);
ibit = 1;
iln = 1;
idx = 1;
partflg = 0;
for i =1:1:nrow
    %count single bit vaules                
    if (M(i) == 1) & (B(i) == 1)
        %capture partial lines (< N-bits)
        nsb(idx) = 1;        
        if (ibit < N(i)) 
            %don't increment count when last index
            if i < nrow                              
                %partial line when previous line was N-bits
                if (M(i+1) > 1) | (B(i+1) > 1)
                    nln(idx) = 1;
                    nval(idx) = ibit;
                    nfl(idx) = N(i)-ibit;
                    idx = idx + 1;
                    ibit = 1;
                else
                    ibit = ibit + 1;
                end;                
            else
                %partial line because last index
                nln(idx) = 1;
                nval(idx) = ibit;
                nfl(idx) = N(i)-ibit;
                ibit = 1;                
            end;
        else                
            nln(idx) = 1;
            nval(idx) = ibit;
            nfl(idx) = N(i)-ibit;
            idx = idx + 1;
            ibit = 1;
        end;            
    else    
        %count multi-bit values       
        if M(i) > 1            
            if mod(N(i),B(i)) == 0%even multiple of line bits
                nln(idx) = ceil(M(i))/(ceil(N(i)/B(i)));
                nval(idx) = ceil(N(i)/B(i));
                nfl(idx) = N(i)-ceil(N(i)/B(i))*4;
            else%partial line, needs fill
                nln(idx) = M(i);
                nval(idx) = 1;
                %nfl(idx) = N(i)-strlength(default(i))*4;
                nfl(idx) = N(i)-B(i);
            end;
        else%partial line, needs fill
            nln(idx) = 1;
            nval(idx) = 1;
            %nfl(idx) = N(i)-strlength(default(i))*4;
            nfl(idx) = N(i)-B(i);
        end;            
        idx = idx + 1;        
    end;    
end;
idxlut = [nln' nval' nsb' nfl'];

twh = {'when'};
tsp = {' '};
ttb = {'    '};
tto = {'=>'};
ttk = {''''};
top = {'UX"'};
tfl = {'0"'};
tcp = {'"'};
tct = {' &'};
tdc = {'10#'};
tpd = {'#'};
tcn = {';'};
tdo = {'cfg_out <= '};
tlo = {'len_out <= '};
tln = tdo;
iln = 1;
idf = 0;
nsbflag = 0;
flflag = 0;

for i =1:1:idx    
    j = nln(i);%number of same type lines
    k = nval(i);%number of values on line    
    if nsbflag == 0%flag so don't increment twice for single bit
        idf = idf + 1;
    end;    
    for x = 1:1:j        
        %add fill bits to front of line
        if nfl(i) > 0            
            fltxt = strcat(num2str(nfl(i)),top,tfl);
            tln = strcat(tln,fltxt,tct,tsp);
            flflag = 1;
        end;        
        for y = 1:1:k           
            %calculate number valid bit in line
            if nfl(i) > 0
                lenhex = dec2hex(N(idf)-nfl(i),2);
            else
                lenhex = dec2hex(N(idf),2);
            end;
            %build default value base on number of bit in line
            if nsb(i) == 0
                if B(idf) > 1
                    deftxt = strcat(num2str(B(idf)),top,default(idf),tcp);
                else
                    deftxt = strcat(ttk,default(idf),ttk);
                end;
            else
                deftxt = strcat(ttk,default(idf),ttk);
            end;
            %find end of line
            if y < k
                tln = strcat(tln,deftxt,tct,tsp);
            else
                tln = strcat(tln,deftxt,tcn);
            end;
            %calculate default index and set flag
            if nsb(i) == 1
                idf = idf + 1;
                nsbflag = 1;
            else
                nsbflag= 0;
            end;                        
        end;
        %branch text
        branch(1,iln) = strcat(twh,tsp,tdc,num2str(iln-1),tpd,tsp,tto);
        %control text
        ctrl(1,iln) = tln;
        %valid bits in line text
        len(1,iln) = strcat(tlo,'5',top,lenhex,tcp,tcn);
        tln = tdo;
        iln = iln + 1;        
    end;        
end;

%write teh HDL file
%########################################
fid = fopen('citiroc_rom.vhd','wt');           
fprintf(fid,'%s\n','library ieee;');
fprintf(fid,'%s%s\n',string(ttb),'use ieee.std_logic_1164.all;');
fprintf(fid,'%s%s\n',string(ttb),'use ieee.numeric_std.all;');
fprintf(fid,'\n\n');
%arch stuff
fprintf(fid,'%s\n','entity citiroc_cfg_rom is');
fprintf(fid,'%s\n','port(');
fprintf(fid,'%s%s%s%s\n',string(ttb),'clk',string(strcat(ttb,ttb,ttb,ttb,ttb)),': in std_logic;');
fprintf(fid,'%s%s%s%s\n',string(ttb),'ce',string(strcat(ttb,ttb,ttb,ttb,ttb)),': in std_logic;');
fprintf(fid,'%s%s%s%s\n',string(ttb),'reset',string(strcat(ttb,ttb,ttb,ttb,ttb)),': in std_logic;');
fprintf(fid,'%s%s%s%s%s%s%s\n',string(ttb),'cfg_adr',string(strcat(ttb,ttb,ttb,ttb,ttb)),': in integer range 0 to',string(tsp),num2str(numel(ctrl)-1),';');
fprintf(fid,'%s%s%s%s\n',string(ttb),'cfg_out',string(strcat(ttb,ttb,ttb,ttb,ttb)),': out std_logic_vector(15 downto 0);');
fprintf(fid,'%s%s%s%s\n',string(ttb),'len_out',string(strcat(ttb,ttb,ttb,ttb,ttb)),': out std_logic_vector(15 downto 0));');
fprintf(fid,'%s\n','end entity;');
fprintf(fid,'\n\n');
fprintf(fid,'%s\n','architecture cfg_default of citiroc_cfg_rom is');
fprintf(fid,'\n');
fprintf(fid,'%s\n','begin');
fprintf(fid,'\n');
%control register value ROM process
fprintf(fid,'%s%s\n',string(ttb),'cfg_rom_pcs : process(clk)');
fprintf(fid,'%s%s\n',string(ttb),'begin');
fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'if clk''event and clk=''1'' then');
fprintf(fid,'%s%s\n',string(strcat(ttb,ttb,ttb)),'case cfg_adr is');
for i = 1:1:iln-1
 fprintf(fid,'%s%s\n',string(strcat(ttb,ttb,ttb)),string(branch(i)));
 fprintf(fid,'%s%s\n',string(strcat(ttb,ttb,ttb,ttb)),ctrl(i));
end;
fprintf(fid,'%s%s\n',string(strcat(ttb,ttb,ttb)),'when others =>');
fprintf(fid,'%s%s\n',string(strcat(ttb,ttb,ttb,ttb)),ctrl(1)); 
fprintf(fid,'%s%s\n',string(strcat(ttb,ttb,ttb)),'end case;');
fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'end if;');
fprintf(fid,'%s%s\n',string(ttb),'end process;');
fprintf(fid,'\n\n');
%control register length ROM process
fprintf(fid,'%s%s\n',string(ttb),'len_pcs : process(clk)');
fprintf(fid,'%s%s\n',string(ttb),'begin');
fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'if clk''event and clk=''1'' then');
fprintf(fid,'%s%s\n',string(strcat(ttb,ttb,ttb)),'case cfg_adr is');
for i = 1:1:iln-1
 fprintf(fid,'%s%s\n',string(strcat(ttb,ttb,ttb)),string(branch(i)));
 fprintf(fid,'%s%s\n',string(strcat(ttb,ttb,ttb,ttb)),string(len(i)));
end;
fprintf(fid,'%s%s\n',string(strcat(ttb,ttb,ttb)),'when others =>');
fprintf(fid,'%s%s\n',string(strcat(ttb,ttb,ttb,ttb)),string(len(1))); 
fprintf(fid,'%s%s\n',string(strcat(ttb,ttb,ttb)),'end case;');
fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'end if;');
fprintf(fid,'%s%s\n',string(ttb),'end process;');
fprintf(fid,'\n\n');
%end the arch
fprintf(fid,'%s\n','end cfg_default;');
fclose(fid);
