%% QPSK Constellation + SNR/EbN0/EVM + MATLAB Slicer + BER Curve from ILA CSV
clear; clc;
close all;

% Ask user at runtime: Jitter = "noise" for demo constellation
choice = input('Plot noisy constellation? (0 = NO, 1 = YES): ');
if isempty(choice)
    choice = 0;   % default
end
Jitter = logical(choice);

fname   = 'iladata_1.csv';
hex_col = "rx_sl_in_tdata[31:0]";
sigma   = 0.02;       % jitter std-dev (for demo only)

%% 1) Read CSV and clean
T = readtable(fname, 'VariableNamingRule', 'preserve');

% Remove "Radix" row
T(1,:) = [];

% Drop blank/missing words
mask = ~ismissing(T.(hex_col));
T = T(mask,:);

% Extract handshake
tvalid = hex2dec(string(T.rx_sl_in_tvalid));
tready = hex2dec(string(T.rx_sl_in_tready));
use    = (tvalid == 1) & (tready == 1);

data_hex = T.(hex_col);
data_hex = data_hex(use);

%% 2) Convert hex → uint32
w = uint32(hex2dec(string(data_hex)));

%% 3) Extract I and Q (signed 16-bit)
I_u16 = uint16(bitshift(w, -16));          % [31:16]
Q_u16 = uint16(bitand(w, uint32(65535)));  % [15:0]

I_raw = typecast(I_u16, 'int16');
Q_raw = typecast(Q_u16, 'int16');

%% 4) Convert to Q1.15 floating point
I_no_fuzz = double(I_raw) / 32768;
Q_no_fuzz = double(Q_raw) / 32768;

% Keep a clean copy for BER simulation
I_clean = I_no_fuzz;
Q_clean = Q_no_fuzz;

% Optional Jitter for demo constellation / SNR
if Jitter == 1
    I = I_no_fuzz + sigma * randn(size(I_no_fuzz));
    Q = Q_no_fuzz + sigma * randn(size(Q_no_fuzz));
else
    I = I_no_fuzz;
    Q = Q_no_fuzz;
end

fprintf("Parsed %d symbols.\n", numel(I));

%% 5) Compute ideal symbols from actual centroids (per quadrant)
q_pp = (I > 0) & (Q > 0);   % +I, +Q
q_pn = (I > 0) & (Q < 0);   % +I, -Q
q_np = (I < 0) & (Q > 0);   % -I, +Q
q_nn = (I < 0) & (Q < 0);   % -I, -Q

if any([sum(q_pp), sum(q_pn), sum(q_np), sum(q_nn)] == 0)
    error('One of the QPSK quadrants has no points – check the data.');
end

c_pp = [mean(I(q_pp)), mean(Q(q_pp))];
c_pn = [mean(I(q_pn)), mean(Q(q_pn))];
c_np = [mean(I(q_np)), mean(Q(q_np))];
c_nn = [mean(I(q_nn)), mean(Q(q_nn))];

ideal_I = zeros(size(I));
ideal_Q = zeros(size(Q));

ideal_I(q_pp) = c_pp(1);  ideal_Q(q_pp) = c_pp(2);
ideal_I(q_pn) = c_pn(1);  ideal_Q(q_pn) = c_pn(2);
ideal_I(q_np) = c_np(1);  ideal_Q(q_np) = c_np(2);
ideal_I(q_nn) = c_nn(1);  ideal_Q(q_nn) = c_nn(2);

%% 6) Error, noise power, SNR, EVM, Eb/N0 (for current jitter setting)
err_I = I - ideal_I;
err_Q = Q - ideal_Q;

err_sq    = err_I.^2 + err_Q.^2;
noise_var = mean(err_sq);
sig_power = mean(ideal_I.^2 + ideal_Q.^2);

SNR_linear = sig_power / noise_var;
SNR_dB     = 10*log10(SNR_linear);

EVM_rms     = sqrt(noise_var / sig_power);
EVM_percent = 100 * EVM_rms;

% QPSK: 2 bits per symbol
EbN0_linear = SNR_linear / 2;
EbN0_dB     = 10*log10(EbN0_linear);

%% 7) Print results for this capture / jitter setting
fprintf('\n=============================\n');
fprintf('   QPSK SNR/EbN0 Results\n');
fprintf('=============================\n');
fprintf('SNR      = %.2f dB\n', SNR_dB);
fprintf('Eb/N0    = %.2f dB\n', EbN0_dB);
fprintf('EVM      = %.2f %%\n', EVM_percent);
fprintf('Signal P = %.4f\n', sig_power);
fprintf('Noise P  = %.4f\n', noise_var);
fprintf('=============================\n\n');

%% 8) Plot constellation
figure;
plot(I, Q, '.', 'MarkerSize', 25); hold on;
plot(ideal_I, ideal_Q, 'rx', 'MarkerSize', 10, 'LineWidth', 1.5);
grid on; axis equal;
xlabel('I'); ylabel('Q');
title(sprintf('QPSK Constellation (SNR=%.1f dB, EVM=%.1f%%)', ...
      SNR_dB, EVM_percent));
legend('Samples','Quadrant centroids','Location','best');

%% 9) MATLAB QPSK HARD SLICER (for current I/Q → bytes)
% Sign-based mapping:
% bit = 0 for positive, 1 for negative
I_sign = sign(I);
Q_sign = sign(Q);
I_sign(I_sign == 0) = 1;
Q_sign(Q_sign == 0) = 1;

bitI = uint8(I_sign < 0);
bitQ = uint8(Q_sign < 0);

sym_bits  = [bitI, bitQ].';     % 2 x N
bitstream = sym_bits(:);        % 2N x 1

nBits  = numel(bitstream);
nBytes = floor(nBits / 8);
bitstream_trunc = bitstream(1:8*nBytes);

bits_mat = reshape(bitstream_trunc, 8, []).';            % [Nbytes x 8]
rx_bytes = uint8( bi2de(bits_mat, 'left-msb') );

fprintf('Recovered %d bytes from MATLAB slicer (current I/Q).\n', numel(rx_bytes));

%% 10) BER vs Eb/N0 curve using AWGN on *captured clean* constellation
% We treat I_clean/Q_clean as the "true" symbols (no extra jitter).
% Then we add AWGN in MATLAB and compare hard-sliced bits vs reference bits.

% Reference bits from clean (no-jitter) data
Ic = I_clean;
Qc = Q_clean;

Ic_sign = sign(Ic);
Qc_sign = sign(Qc);
Ic_sign(Ic_sign == 0) = 1;
Qc_sign(Qc_sign == 0) = 1;

bitI_ref = uint8(Ic_sign < 0);
bitQ_ref = uint8(Qc_sign < 0);
sym_bits_ref  = [bitI_ref, bitQ_ref].';
bits_ref = sym_bits_ref(:);

% Symbol energy from clean capture
Es = mean(Ic.^2 + Qc.^2);

% SNR / EbN0 sweep
SNRdB_vec = 0:2:20;             % adjust as you like
BER      = zeros(size(SNRdB_vec));
EbN0dB_vec = zeros(size(SNRdB_vec));

for k = 1:length(SNRdB_vec)
    SNRdB = SNRdB_vec(k);
    SNR_lin = 10^(SNRdB/10);

    % For QPSK in complex baseband: N0 = Es / SNR
    N0 = Es / SNR_lin;
    sigma2 = N0/2;
    sigma_awgn = sqrt(sigma2);

    % Add AWGN to clean constellation
    nI = sigma_awgn * randn(size(Ic));
    nQ = sigma_awgn * randn(size(Qc));

    In = Ic + nI;
    Qn = Qc + nQ;

    % Slice noisy constellation to bits
    In_sign = sign(In);
    Qn_sign = sign(Qn);
    In_sign(In_sign == 0) = 1;
    Qn_sign(Qn_sign == 0) = 1;

    bitI_n = uint8(In_sign < 0);
    bitQ_n = uint8(Qn_sign < 0);
    sym_bits_n = [bitI_n, bitQ_n].';
    bits_n = sym_bits_n(:);

    % BER vs reference bits
    Nbits = min(numel(bits_ref), numel(bits_n));
    BER(k) = mean(bits_ref(1:Nbits) ~= bits_n(1:Nbits));

    % Corresponding Eb/N0 (QPSK: 2 bits/symbol)
    EbN0_lin = SNR_lin / 2;
    EbN0dB_vec(k) = 10*log10(EbN0_lin);
end

% Plot BER curve
figure;
semilogy(EbN0dB_vec, BER, 'o-','LineWidth',1.5); grid on;
xlabel('E_b/N_0 (dB)');
ylabel('BER');
% AWGN added in MATLAB using captured constellation, ideally the noise
% injector RTL would add the AWGN-like noise
title('BER vs E_b/N_0');

fprintf('BER sweep done over Eb/N0 in [%.1f, %.1f] dB.\n', ...
    min(EbN0dB_vec), max(EbN0dB_vec));
