package com.example.android2pc;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.KeyEvent;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.widget.ArrayAdapter;
import android.widget.AutoCompleteTextView;
import android.widget.EditText;
import android.widget.Filter;
import android.widget.TextView;
import android.widget.Toast;
import android.media.AudioManager;
import android.media.ToneGenerator;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class MainActivity extends Activity {

    private AutoCompleteTextView etIpAddress;
    private EditText etMessage;
    private static final int PORT = 11000;
    private static final String PREFS_NAME = "AppPrefs";
    private static final String KEY_HISTORY = "IpHistory";
    private NoFilterAdapter adapter; // Use custom adapter
    private List<String> historyList;
    private ToneGenerator toneGenerator;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        try {
            toneGenerator = new ToneGenerator(AudioManager.STREAM_MUSIC, 100);
        } catch (RuntimeException e) {
            e.printStackTrace();
        }

        etIpAddress = findViewById(R.id.et_ip_address);
        etMessage = findViewById(R.id.et_message);

        // Load History
        historyList = loadHistory();
        // Use custom adapter that doesn't filter
        adapter = new NoFilterAdapter(this, android.R.layout.simple_dropdown_item_1line, historyList);
        etIpAddress.setAdapter(adapter);
        
        // Auto fill the last used IP
        if (!historyList.isEmpty()) {
            etIpAddress.setText(historyList.get(0));
            // Move cursor to end
            etIpAddress.setSelection(etIpAddress.getText().length());
        }

        // Show dropdown when clicked or focused
        etIpAddress.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                etIpAddress.showDropDown();
            }
        });
        
        etIpAddress.setOnFocusChangeListener(new View.OnFocusChangeListener() {
            @Override
            public void onFocusChange(View v, boolean hasFocus) {
                if (hasFocus) {
                    etIpAddress.showDropDown();
                }
            }
        });

        // Listen for "Send" action on soft keyboard
        etMessage.setOnEditorActionListener(new TextView.OnEditorActionListener() {
            @Override
            public boolean onEditorAction(TextView v, int actionId, KeyEvent event) {
                // Check for IME_ACTION_SEND or Enter key press
                if (actionId == EditorInfo.IME_ACTION_SEND || 
                    actionId == EditorInfo.IME_ACTION_DONE ||
                    (event != null && event.getKeyCode() == KeyEvent.KEYCODE_ENTER && event.getAction() == KeyEvent.ACTION_DOWN)) {
                    
                    performSend();
                    return true; // Consume the event
                }
                return false;
            }
        });
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (toneGenerator != null) {
            toneGenerator.release();
            toneGenerator = null;
        }
    }

    private void performSend() {
        String ip = etIpAddress.getText().toString().trim();
        String message = etMessage.getText().toString();

        if (ip.isEmpty()) {
            Toast.makeText(MainActivity.this, "Please enter IP", Toast.LENGTH_SHORT).show();
            return;
        }
        if (message.isEmpty()) {
            Toast.makeText(MainActivity.this, "Message is empty", Toast.LENGTH_SHORT).show();
            return;
        }

        sendMessage(ip, message);
    }

    private void sendMessage(final String ip, final String message) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                DatagramSocket socket = null;
                try {
                    socket = new DatagramSocket();
                    InetAddress address = InetAddress.getByName(ip);
                    byte[] data = message.getBytes("UTF-8");
                    DatagramPacket packet = new DatagramPacket(data, data.length, address, PORT);
                    socket.send(packet);

                    // Wait for ACK
                    socket.setSoTimeout(2000); // 2s timeout
                    byte[] ackBuf = new byte[256];
                    DatagramPacket ackPacket = new DatagramPacket(ackBuf, ackBuf.length);
                    socket.receive(ackPacket);

                    new Handler(Looper.getMainLooper()).post(new Runnable() {
                        @Override
                        public void run() {
                            Toast.makeText(MainActivity.this, "Sent!", Toast.LENGTH_SHORT).show();
                            etMessage.setText(""); // Auto clear message
                            saveIp(ip); // Save IP after success
                            if (toneGenerator != null) {
                                toneGenerator.startTone(ToneGenerator.TONE_PROP_ACK);
                            }
                        }
                    });

                } catch (java.net.SocketTimeoutException e) {
                    new Handler(Looper.getMainLooper()).post(new Runnable() {
                        @Override
                        public void run() {
                            Toast.makeText(MainActivity.this, "Timeout: No response from PC", Toast.LENGTH_SHORT).show();
                            if (toneGenerator != null) {
                                toneGenerator.startTone(ToneGenerator.TONE_PROP_NACK);
                            }
                        }
                    });
                } catch (Exception e) {
                    e.printStackTrace();
                    final String errorMsg = e.getMessage();
                    new Handler(Looper.getMainLooper()).post(new Runnable() {
                        @Override
                        public void run() {
                            Toast.makeText(MainActivity.this, "Error: " + errorMsg, Toast.LENGTH_LONG).show();
                            if (toneGenerator != null) {
                                toneGenerator.startTone(ToneGenerator.TONE_PROP_NACK);
                            }
                        }
                    });
                } finally {
                    if (socket != null) {
                        socket.close();
                    }
                }
            }
        }).start();
    }

    private List<String> loadHistory() {
        SharedPreferences prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        String historyStr = prefs.getString(KEY_HISTORY, "");
        List<String> list = new ArrayList<>();
        if (!historyStr.isEmpty()) {
            String[] items = historyStr.split(",");
            list.addAll(Arrays.asList(items));
        }
        return list;
    }

    private void saveIp(String ip) {
        // Move current IP to top
        historyList.remove(ip);
        historyList.add(0, ip);
        
        // Limit history size (e.g. 5)
        if (historyList.size() > 5) {
            historyList = historyList.subList(0, 5);
        }

        // Update adapter (re-create to ensure data sync with custom adapter)
        adapter = new NoFilterAdapter(this, android.R.layout.simple_dropdown_item_1line, historyList);
        etIpAddress.setAdapter(adapter);

        // Save to prefs
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < historyList.size(); i++) {
            sb.append(historyList.get(i));
            if (i < historyList.size() - 1) {
                sb.append(",");
            }
        }
        SharedPreferences prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        prefs.edit().putString(KEY_HISTORY, sb.toString()).apply();
    }

    // Custom Adapter that disables filtering
    private class NoFilterAdapter extends ArrayAdapter<String> {
        private List<String> items;

        public NoFilterAdapter(Context context, int resource, List<String> objects) {
            super(context, resource, objects);
            this.items = objects;
        }

        @Override
        public Filter getFilter() {
            return new Filter() {
                @Override
                protected FilterResults performFiltering(CharSequence constraint) {
                    FilterResults results = new FilterResults();
                    results.values = items;
                    results.count = items.size();
                    return results;
                }

                @Override
                protected void publishResults(CharSequence constraint, FilterResults results) {
                    notifyDataSetChanged();
                }
            };
        }
    }
}
