function gen_mapper_golden(mode, frameLenSyms, nFrames, seed, outDir)
% Golden vector generator for mapper.sv
% - mode: 'bpsk' or 'qpsk'
% - frameLenSyms: symbols per frame (ensure K*frameLenSyms is byte-aligned)
% - nFrames: number of frames to generate
% - seed: RNG seed for repeatability
% - outDir: output folder (created if missing)
%
% Usage: 

% Example 1: QPSK, 256 syms/frame, 3 frames
% gen_mapper_golden('qpsk', 256, 3, 42, './golden');

% Example 2: BPSK, 512 syms/frame, 2 frames
% gen_mapper_golden('bpsk', 512, 2, 123, './golden_bpsk');

% Outputs (CSV with headers):
%   mapper_in_bytes.csv   : byte_idx, data, tlast
%   mapper_golden_syms.csv: sym_idx, I, Q, tlast, b0, b1, K, phase_deg
%
% Conventions (matches CDR):
% - Bit packing to bytes is LITTLE-ENDIAN (first bit goes to bit 0).
% - Q1.15 scaling for I/Q (int16).
% QPSK is Gray-coded with bit pair [b0 b1] (LSB-first within a symbol)
% New convention:
%   I sign = b0,  Q sign = b1
%   Mapping: [b0 b1] = 00→(+,+), 01→(+,-), 11→(-,-), 10→(-,+) 
% Amplitude = 1/sqrt(2) before Q1.15 quantize.

arguments
    mode (1,:) char {mustBeMember(mode,["bpsk","qpsk"])}
    frameLenSyms (1,1) {mustBeInteger,mustBePositive}
    nFrames (1,1) {mustBeInteger,mustBePositive}
    seed (1,1) {mustBeNumeric}
    outDir (1,:) char
end

if ~exist(outDir,'dir'); mkdir(outDir); end
rng(seed);

% --- Parameters
switch mode
    case 'bpsk', K = 1;  % bits per symbol
    case 'qpsk', K = 2;
end
bitsPerFrame = K * frameLenSyms;
if mod(bitsPerFrame,8) ~= 0
    error('K*frameLenSyms must be a multiple of 8 so TLAST aligns on byte boundaries.');
end
totalSyms = frameLenSyms * nFrames;
totalBits = bitsPerFrame * nFrames;
scaleQ115 = 32767;                % full scale for Q1.15
oneOverRoot2 = 1/sqrt(2);         % for QPSK Gray points

% --- Generate deterministic input bits (use RNG seed)
bits = uint8(randi([0 1], totalBits, 1)); % column vector

% --- Form symbols and expected I/Q
sym_b0 = zeros(totalSyms,1,'uint8'); % first bit of the symbol (LSB-first)
sym_b1 = zeros(totalSyms,1,'uint8'); % second bit (QPSK only), 0 for BPSK
I = zeros(totalSyms,1,'double');
Q = zeros(totalSyms,1,'double');

if K==1
    % BPSK: one bit per symbol; 0 -> +1, 1 -> -1 (real axis)
    sym_b0 = bits; % store for trace
    I =  double(1 - 2*sym_b0); % +1 for 0, -1 for 1
    Q(:) = 0;
else
    % --- QPSK (K=2), LSB-first per symbol: bits = [b0 b1]
    bp     = reshape(bits, 2, []).';
    sym_b0 = bp(:,1);                    % first (LSB-in-byte) bit → drives I sign  (NEW)
    sym_b1 = bp(:,2);                    % second bit            → drives Q sign  (NEW)
    
    % I from b0, Q from b1 (Gray; magnitude = 1/sqrt(2))
    I = (1 - 2*double(sym_b0)) * oneOverRoot2;
    Q = (1 - 2*double(sym_b1)) * oneOverRoot2;
end

% --- Compute TLAST for symbols (frame end)
tlast_syms = zeros(totalSyms,1,'uint8');
for f = 1:nFrames
    tlast_syms(f*frameLenSyms) = 1;
end

% --- Quantize to Q1.15 int16
I_q15 = int16(max(min(round(I * scaleQ115),  32767), -32768));
Q_q15 = int16(max(min(round(Q * scaleQ115),  32767), -32768));

% --- Phase (degrees) for trace/debug
phase_deg = int16(round(atan2d(double(Q), double(I)))); % [-180,180]

% --- Write mapper_golden_syms.csv
sym_idx = (0:totalSyms-1).';
T_syms = table(sym_idx, I_q15, Q_q15, tlast_syms, sym_b0, sym_b1, ...
               repmat(uint8(K), totalSyms,1), phase_deg, ...
               'VariableNames', {'sym_idx','I','Q','tlast','b0','b1','K','phase_deg'});
writetable(T_syms, fullfile(outDir,'mapper_golden_syms.csv'));

% --- Pack bits to little-endian bytes (first bit -> bit0)
bytesPerFrame = bitsPerFrame/8;
B = reshape(bits, 8, []).';                 % rows of 8 bits: [b0 b1 ... b7]
weights = uint8(2.^(0:7));                  % little-endian weights
data_bytes = uint8(sum(B .* weights, 2));   % decimal 0..255

% --- TLAST for input bytes (frame end)
tlast_bytes = zeros(numel(data_bytes),1,'uint8');
for f = 1:nFrames
    tlast_bytes(f*bytesPerFrame) = 1;
end

% --- Write mapper_in_bytes.csv
byte_idx = (0:numel(data_bytes)-1).';
T_in = table(byte_idx, data_bytes, tlast_bytes, ...
             'VariableNames', {'byte_idx','data','tlast'});
writetable(T_in, fullfile(outDir,'mapper_in_bytes.csv'));

fprintf('Wrote %s and %s\n', ...
    fullfile(outDir,'mapper_in_bytes.csv'), ...
    fullfile(outDir,'mapper_golden_syms.csv'));
end
