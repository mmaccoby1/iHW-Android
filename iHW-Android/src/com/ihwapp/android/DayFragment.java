package com.ihwapp.android;

import java.util.*;

import com.ihwapp.android.model.*;
import com.ihwapp.android.model.Date;

import android.support.v4.app.Fragment;
import android.support.v4.app.FragmentTransaction;
import android.app.Activity;
import android.graphics.Typeface;
import android.os.Bundle;
import android.util.Log;
import android.view.*;
import android.widget.*;

public class DayFragment extends Fragment {
	private Date date;
	private Day day;
	private int initScrollPos;
	private ArrayList<OnFragmentVisibilityChangedListener> ofvcls;
	private Timer countdownTimer;
	private View countdownView;
	private ArrayList<ViewGroup> periodViews;
	
	/*****LIFECYCLE -- BEGINNINGS*****/
	
	public void setArguments(Bundle b) {
		date = new Date(b.getString("date"));
	}
	
	public void onAttach(Activity activity) {
		super.onAttach(activity);
		day = Curriculum.getCurrentCurriculum().getDay(date);
		Log.d("iHW-lc", "DayFragment onAttach: " + date);
	}
	
	public void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		initScrollPos = 0;
		ofvcls = new ArrayList<OnFragmentVisibilityChangedListener>();
		if (savedInstanceState != null && savedInstanceState.containsKey("date")) {
			setArguments(savedInstanceState);
			initScrollPos = savedInstanceState.getInt("scrollPos");
		}
		Log.d("iHW-lc", "DayFragment onCreate: " + date);
	}

	public View onCreateView(final LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
		if (day==null) day = Curriculum.getCurrentCurriculum().getDay(date);
		Log.d("iHW-lc", "DayFragment onCreateView: " + date);
		final View v = inflater.inflate(R.layout.fragment_day, null);
		//Typeface georgiaBold = Typeface.createFromAsset(getActivity().getAssets(), "fonts/Georgia Bold.ttf");
		/*Date d = day.getDate();
		String weekdayName = d.getDisplayName(GregorianCalendar.DAY_OF_WEEK, GregorianCalendar.SHORT, Locale.getDefault());
		String title = weekdayName + ", " + d.toString();
		if (day instanceof NormalDay && ((NormalDay)day).getDayNumber() > 0) title += " (Day " + ((NormalDay)day).getDayNumber() + ")";
		((TextView)v.findViewById(R.id.date_view)).setText(title);*/
		TextView titleText = ((TextView)v.findViewById(R.id.date_view));
		titleText.setText(day.getTitle());
		titleText.setTypeface(Typeface.SERIF, Typeface.BOLD);
		
		//if (day instanceof NormalDay) ((NormalDay)day).fillPeriods(Curriculum.getCurrentCurriculum(getActivity()));
		ArrayList<Period> pds = day.getPeriods();
		
		LinearLayout pdsLayout = ((LinearLayout)v.findViewById(R.id.layout_periods));
		periodViews = new ArrayList<ViewGroup>(pds.size());
		FragmentTransaction transaction = DayFragment.this.getChildFragmentManager().beginTransaction();
		for (int i=0; i<pds.size(); i++) {
			final Period p = pds.get(i);
			final View periodView = inflater.inflate(R.layout.view_period, null);
			periodViews.add((ViewGroup)periodView);
			((TextView)periodView.findViewById(R.id.text_periodnum)).setTypeface(Typeface.SERIF, Typeface.BOLD);
			if (p.getNum() > 0) {
				((TextView)periodView.findViewById(R.id.text_periodnum)).setText(getOrdinal(p.getNum()));
			}
			((TextView)periodView.findViewById(R.id.text_title)).setText(p.getName());
			((TextView)periodView.findViewById(R.id.text_starttime)).setText(p.getStartTime().toString12());
			((TextView)periodView.findViewById(R.id.text_endtime)).setText(p.getEndTime().toString12());
			FrameLayout fl = new FrameLayout(getActivity());
			int id=day.getDate().getDay()*100+i;
			fl.setId(id);
			((LinearLayout)periodView.findViewById(R.id.layout_right)).addView(fl);
			PeriodNotesFragment f = PeriodNotesFragment.newInstance(day.getDate(), i);
			transaction.add(id, f, day.getDate().toString() + ":" + i);
			pdsLayout.addView(periodView);
			pdsLayout.addView(new Separator(getActivity()));
		}
		transaction.commit();
		TextView moreNotesLabel = new TextView(getActivity());
		if (pds.size() > 0) moreNotesLabel.setText("Additional Notes");
		else moreNotesLabel.setText("Notes");
		pdsLayout.addView(moreNotesLabel);
		PeriodNotesFragment f = PeriodNotesFragment.newInstance(day.getDate(), -1);
		DayFragment.this.addOnFragmentVisibilityChangedListener(f);
		DayFragment.this.getChildFragmentManager().beginTransaction().replace(R.id.layout_periods, f, day.getDate().toString() + ":-1").commit();
		
		String dayName = "";
		if (day instanceof Holiday) {
			dayName = ((Holiday)day).getName();
		}
		TextView dayNameText = ((TextView)v.findViewById(R.id.text_day_title));
		dayNameText.setTypeface(Typeface.SERIF, Typeface.BOLD);
		if (dayName.equals("")) dayNameText.setVisibility(View.GONE);
		else dayNameText.setText(dayName);
		this.getChildFragmentManager().beginTransaction().replace(R.id.layout_periods, f, day.getDate().toString() + ":-1").commit();
		return v;
	}
	
	public void onStart() {
		super.onStart();
		Log.d("iHW-lc", "DayFragment onStart: " + date);
		/*ArrayList<Period> pds = day.getPeriods();
		//FragmentTransaction transaction = this.getChildFragmentManager().beginTransaction();
		for (int i=0; i<pds.size(); i++) {
			final Period p = pds.get(i);
			/*int id=day.getDate().getDay()*100+i;
			if (getView().findViewById(id) != null) {
				PeriodNotesFragment f = PeriodNotesFragment.newInstance(day.getDate(), i);
				transaction.add(id, f, day.getDate().toString() + ":" + i);
			}*
			int minsUntil = new Time().minutesUntil(p.getStartTime());
			//TODO fix criteria for timer being shown:
			if (day.getDate().equals(new Date()) && minsUntil < p.getStartTime().minutesUntil(p.getEndTime()) && minsUntil > 0) {
				this.addCountdownTimerToPeriod(p, periodViews.get(i));
			}
		}*/
	}
	
	public void onResume() {
		super.onResume();
		Log.d("iHW-lc", "DayFragment onResume: " + date);
		final ScrollView sv = (ScrollView)getView().findViewById(R.id.scroll_periods);
		sv.post(new Runnable() { 
			public void run() { 
				sv.scrollTo(0, initScrollPos);
			} 
		});
	}
	
	/*****LIFECYCLE -- ENDINGS*****/
	
	public void onSaveInstanceState(Bundle outState) {
		super.onSaveInstanceState(outState);
		Log.d("iHW-lc", "DayFragment onSaveInstanceState: " + date);
		//outState.putString("dayJSON", day.saveDay().toString());
		outState.putString("date", date.toString());
		outState.putInt("scrollPos", ((ScrollView)getView().findViewById(R.id.scroll_periods)).getScrollY());
	}
	
	public void onPause() {
		super.onPause();
		Log.d("iHW-lc", "DayFragment onPause: " + date);
		initScrollPos = ((ScrollView)getView().findViewById(R.id.scroll_periods)).getScrollY();
	}
	
	public void onStop() {
		super.onStop();
		Log.d("iHW-lc", "DayFragment onStop: " + date);
		if (countdownTimer != null) countdownTimer.cancel();
		countdownTimer = null;
		if (countdownView != null) countdownView.setVisibility(View.GONE);
		countdownView = null;
	}
	
	public void onDestroyView() {
		Log.d("iHW-lc", "DayFragment onDestroyView: " + date);
		periodViews.clear();
		periodViews = null;
		countdownView = null;
		((ViewGroup)this.getView()).removeAllViews();
		super.onDestroyView();
	}
	
	/*****OTHER METHODS*****/
	
	public void resetCountdownTimer() {
		countdownTimer.cancel();
		countdownTimer = null;
		countdownView.setVisibility(View.GONE);
		countdownView = null;
		ArrayList<Period> pds = day.getPeriods();
		for (int i=0; i<pds.size(); i++) {
			Period p = pds.get(i);
			int minsUntil = new Time().minutesUntil(p.getStartTime());
			//TODO fix criteria for timer being shown:
			if (day.getDate().equals(new Date()) && minsUntil < p.getStartTime().minutesUntil(p.getEndTime()) && minsUntil > 0) {
				this.addCountdownTimerToPeriod(p, periodViews.get(i));
			}
		}
	}
	
	public void addCountdownTimerToPeriod(final Period p, final View periodView) {
		//Log.d("iHW", i + " " + new Time() + ", " + p.getStartTime());
		if (countdownView != null) countdownView.setVisibility(View.GONE);
		countdownView = periodView.findViewById(R.id.text_countdown);
		countdownView.setVisibility(View.VISIBLE);
		if (countdownTimer != null) countdownTimer.cancel();
		countdownTimer = new Timer();
		countdownTimer.scheduleAtFixedRate(new TimerTask() {
			public void run() {
				getActivity().runOnUiThread(new Runnable() {
					public void run() {
						int minsUntil = new Time().minutesUntil(p.getStartTime());
						int secsUntil = new Time().secondsUntil(p.getStartTime()) % 60;
						if (secsUntil != 0) minsUntil++;
						if (minsUntil <= 0 && secsUntil <= 0) {
							periodView.findViewById(R.id.text_countdown).setVisibility(View.GONE);
							resetCountdownTimer();
							return;
						}
						String secs = "" + secsUntil;
						if (secsUntil < 10) secs = "0" + secs;
						((TextView)periodView.findViewById(R.id.text_countdown)).setText("Starts in " + minsUntil + ":" + secs);
					}
				});
			}
		}, 0, 1000);
	}
	
	public void setUserVisibleHint(boolean isVisibleToUser) {
		Log.d("iHW-lc", "DayFragment setUserVisibleHint: " + isVisibleToUser + "(" + date + ")");
		if (this.getUserVisibleHint() != isVisibleToUser && (this.isVisible() || isVisibleToUser) && ofvcls != null) {
			for (OnFragmentVisibilityChangedListener l : ofvcls) {
				l.onFragmentVisibilityChanged(this, isVisibleToUser);
			}
		}
		super.setUserVisibleHint(isVisibleToUser);
	}
	
	public void addOnFragmentVisibilityChangedListener(OnFragmentVisibilityChangedListener l) { ofvcls.add(l); }
	public void removeOnFragmentVisibilityChangedListener(OnFragmentVisibilityChangedListener l) { ofvcls.remove(l); }
	
	private static String getOrdinal(int num) {
		String suffix = "";
		if (num%10==1) suffix="st";
		else if (num%10==2) suffix="nd";
		else if (num%10==3) suffix="rd";
		else suffix = "th";
		return num+suffix;
	}
	
	public interface OnFragmentVisibilityChangedListener {
		public void onFragmentVisibilityChanged(Fragment f, boolean isVisible);
	}
}