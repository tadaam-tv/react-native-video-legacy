package com.brentvatne.exoplayer.latens;

import android.net.Uri;
import android.text.TextUtils;
import android.util.Base64;
import android.util.Log;

import com.google.android.exoplayer2.C;
import com.google.android.exoplayer2.drm.ExoMediaDrm;
import com.google.android.exoplayer2.drm.MediaDrmCallback;

import java.io.IOException;
import java.io.UnsupportedEncodingException;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import com.google.android.exoplayer2.upstream.DataSourceInputStream;
import com.google.android.exoplayer2.upstream.DataSpec;
import com.google.android.exoplayer2.upstream.HttpDataSource;
import com.google.android.exoplayer2.util.Assertions;
import com.google.android.exoplayer2.util.Util;
import com.google.gson.Gson;

public class LatensMediaDrmCallback implements MediaDrmCallback {

    private static final String TAG = "LatensMediaDrmCallback";

    private final HttpDataSource.Factory dataSourceFactory;

    private String defaultLicenseUrl;

    private String portalId;

    private String customerName;

    public LatensMediaDrmCallback(String defaultLicenseUrl, String portalId, String customerName, HttpDataSource.Factory dataSourceFactory) {
        this.defaultLicenseUrl = defaultLicenseUrl;
        this.portalId = portalId;
        this.customerName = customerName;
        this.dataSourceFactory = dataSourceFactory;
    }

    public void setKeyRequestProperty(String name, String value) {
        // ignore
    }

    public String createLatensRegistration(byte[] payload) {
        LatensDeviceInfo deviceInfo = new LatensDeviceInfo();
        LatensRegistration latensRegistration = new LatensRegistration();
        latensRegistration.customerName = this.customerName;
        latensRegistration.accountName = "PlayReadyAccount";
        latensRegistration.portalId = this.portalId;
        latensRegistration.friendlyName = "tadaam";
        latensRegistration.deviceInfo = deviceInfo;
        LatensRegistrationBody body = new LatensRegistrationBody();
        body.latensRegistration = latensRegistration;
        try {
            body.payload = new String(Base64.encode(payload, 0), "US-ASCII");
        } catch (UnsupportedEncodingException e) {
            e.printStackTrace();
        }
        Gson gson = new Gson();
        String jsonBody = gson.toJson(body);
        Log.d(TAG, jsonBody);
        return Base64.encodeToString(jsonBody.getBytes(), Base64.DEFAULT);
    }

    @Override
    public byte[] executeProvisionRequest(UUID uuid, ExoMediaDrm.ProvisionRequest request) throws IOException {
        String url = request.getDefaultUrl() + "&signedRequest=" + new String(request.getData());
        return executePost(dataSourceFactory, url, new byte[0], null);
    }

    @Override
    public byte[] executeKeyRequest(UUID uuid, ExoMediaDrm.KeyRequest request) throws Exception {
        String url = defaultLicenseUrl;
        String requestBody = createLatensRegistration(request.getData());
        byte[] keyResponse = executePost(dataSourceFactory, url, requestBody.getBytes(), null);
        Gson gson = new Gson();
        String response = new String(keyResponse);
        YeloLicenseResponse license = gson.fromJson(response, YeloLicenseResponse.class);
        return Base64.decode(license.license, Base64.DEFAULT);
    }

    private static byte[] executePost(HttpDataSource.Factory dataSourceFactory, String url,
                                      byte[] data, Map<String, String> requestProperties) throws IOException {
        HttpDataSource dataSource = dataSourceFactory.createDataSource();
        if (requestProperties != null) {
            for (Map.Entry<String, String> requestProperty : requestProperties.entrySet()) {
                dataSource.setRequestProperty(requestProperty.getKey(), requestProperty.getValue());
            }
        }
        DataSpec dataSpec = new DataSpec(Uri.parse(url), data, 0, 0, C.LENGTH_UNSET, null,
                DataSpec.FLAG_ALLOW_GZIP);
        DataSourceInputStream inputStream = new DataSourceInputStream(dataSource, dataSpec);
        try {
            return Util.toByteArray(inputStream);
        } finally {
            Util.closeQuietly(inputStream);
        }
    }
}
